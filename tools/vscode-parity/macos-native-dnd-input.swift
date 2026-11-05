import AppKit
import ApplicationServices
import Darwin
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
  return result == .success ? value : nil
}

func children(of element: AXUIElement) -> [AXUIElement] {
  (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
}

func labels(of element: AXUIElement) -> [String] {
  ["AXIdentifier", "AXLabel", "AXDescription", "AXTitle", "AXValue"]
    .compactMap { attribute(element, $0) as? String }
}

func frame(of element: AXUIElement) -> CGRect? {
  if let frameRaw = attribute(element, "AXFrame"),
     CFGetTypeID(frameRaw) == AXValueGetTypeID()
  {
    let frameValue = frameRaw as! AXValue
    var rect = CGRect.zero
    if AXValueGetValue(frameValue, .cgRect, &rect), !rect.isEmpty {
      return rect
    }
  }

  guard
    let positionRaw = attribute(element, "AXPosition"),
    let sizeRaw = attribute(element, "AXSize"),
    CFGetTypeID(positionRaw) == AXValueGetTypeID(),
    CFGetTypeID(sizeRaw) == AXValueGetTypeID()
  else {
    return nil
  }

  let positionValue = positionRaw as! AXValue
  let sizeValue = sizeRaw as! AXValue
  var position = CGPoint.zero
  var size = CGSize.zero
  guard
    AXValueGetValue(positionValue, .cgPoint, &position),
    AXValueGetValue(sizeValue, .cgSize, &size)
  else {
    return nil
  }
  return CGRect(origin: position, size: size)
}

func postMouseEvent(
  _ type: CGEventType,
  at point: CGPoint,
  source: CGEventSource,
  targetPID: pid_t? = nil
) throws {
  guard
    let event = CGEvent(
      mouseEventSource: source,
      mouseType: type,
      mouseCursorPosition: point,
      mouseButton: .left
    )
  else {
    throw NSError(domain: "AlulaMacDnd", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Could not construct CoreGraphics mouse event"
    ])
  }
  if let targetPID {
    event.postToPid(targetPID)
  } else {
    event.post(tap: .cghidEventTap)
  }
}

func clickWithSystemEvents(at point: CGPoint) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = [
    "-e",
    "tell application \"System Events\" to click at {\(Int(point.x)), \(Int(point.y))}",
  ]
  let output = Pipe()
  let errors = Pipe()
  process.standardOutput = output
  process.standardError = errors

  do {
    try process.run()
  } catch {
    return "could not start osascript: \(error)"
  }

  let deadline = Date().addingTimeInterval(5)
  while process.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
  }
  if process.isRunning {
    process.terminate()
    process.waitUntilExit()
    return "osascript timed out after 5 seconds"
  }

  process.waitUntilExit()
  let standardOutput = String(
    data: output.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
  ) ?? ""
  let standardError = String(
    data: errors.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
  ) ?? ""
  return "status=\(process.terminationStatus), stdout=\(standardOutput), stderr=\(standardError)"
}

func waitForRunningAlula(deadline: Date) -> NSRunningApplication? {
  while Date() < deadline {
    if let app = NSWorkspace.shared.runningApplications.first(where: { app in
      let name = app.localizedName?.lowercased() ?? ""
      let path = app.bundleURL?.path.lowercased() ?? ""
      return name.contains("alula") || path.contains("alula_app.app")
    }) {
      return app
    }
    Thread.sleep(forTimeInterval: 0.25)
  }
  return nil
}

func logAccessibilityDiagnostics(
  app: NSRunningApplication,
  applicationElement: AXUIElement,
  windows: [AXUIElement]
) {
  print(
    "App: name=\(app.localizedName ?? "<nil>"), " +
      "bundle=\(app.bundleURL?.path ?? "<nil>"), pid=\(app.processIdentifier), " +
      "active=\(app.isActive), activationPolicy=\(app.activationPolicy.rawValue), " +
      "trusted=\(AXIsProcessTrusted())"
  )

  func describe(_ label: String, _ element: AXUIElement) {
    var pid: pid_t = 0
    let pidResult = AXUIElementGetPid(element, &pid)
    var names: CFArray?
    let namesResult = AXUIElementCopyAttributeNames(element, &names)
    let attributes = names as? [String] ?? []
    var rawChildren: CFTypeRef?
    let childrenResult = AXUIElementCopyAttributeValue(
      element,
      "AXChildren" as CFString,
      &rawChildren
    )
    let childCount = (rawChildren as? [AXUIElement])?.count
    let focused = attribute(element, "AXFocused") as? Bool
    let main = attribute(element, "AXMain") as? Bool
    print(
      "AX \(label): pid=\(pid) pidStatus=\(pidResult.rawValue), " +
        "attributesStatus=\(namesResult.rawValue), attributes=\(attributes), " +
        "childrenStatus=\(childrenResult.rawValue), childCount=\(String(describing: childCount)), " +
        "focused=\(String(describing: focused)), main=\(String(describing: main)), " +
        "labels=\(labels(of: element)), frame=\(frame(of: element).map(NSStringFromRect) ?? "<no-frame>")"
    )
  }

  describe("application", applicationElement)
  for (index, window) in windows.enumerated() {
    describe("window[\(index)]", window)
  }

  var visited = 0
  func dumpTree(_ element: AXUIElement, depth: Int) {
    guard depth < 12, visited < 300 else { return }
    visited += 1
    let role = attribute(element, "AXRole") as? String ?? "<no-role>"
    let subrole = attribute(element, "AXSubrole") as? String ?? "<no-subrole>"
    let descendants = children(of: element)
    let indentation = String(repeating: " ", count: depth * 2)
    print(
      "AX tree \(indentation)role=\(role) subrole=\(subrole) " +
        "labels=\(labels(of: element)) frame=\(frame(of: element).map(NSStringFromRect) ?? "<no-frame>") " +
        "children=\(descendants.count)"
    )
    for child in descendants { dumpTree(child, depth: depth + 1) }
  }
  for window in windows { dumpTree(window, depth: 0) }

  let onScreenWindows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
  ) as? [[String: Any]] ?? []
  for info in onScreenWindows where
    (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
  {
    let owner = info[kCGWindowOwnerName as String] as? String ?? "<nil>"
    let title = info[kCGWindowName as String] as? String ?? "<nil>"
    let bounds = String(describing: info[kCGWindowBounds as String] ?? "<nil>")
    print("CGWindow: owner=\(owner), title=\(title), bounds=\(bounds)")
  }
}

func layoutPoint(from layout: [String: Any], key: String) throws -> CGPoint {
  guard let coordinates = layout[key] as? [String: Any],
        let x = coordinates["x"] as? Double,
        let y = coordinates["y"] as? Double else {
    throw NSError(domain: "AlulaMacDnd", code: 7, userInfo: [
      NSLocalizedDescriptionKey: "Missing logical coordinates for \(key) in layout.json"
    ])
  }
  return CGPoint(x: CGFloat(x), y: CGFloat(y))
}

func quitThroughNativeMenu(processIdentifier: Int32) throws {
  guard AXIsProcessTrusted() else {
    throw NSError(domain: "AlulaMacDnd", code: 20, userInfo: [
      NSLocalizedDescriptionKey: "Accessibility permission was not granted to this input helper"
    ])
  }
  guard let app = NSRunningApplication(processIdentifier: processIdentifier) else {
    throw NSError(domain: "AlulaMacDnd", code: 21, userInfo: [
      NSLocalizedDescriptionKey: "Could not find the native-titlebar Alula process"
    ])
  }

  _ = app.activate(options: [.activateIgnoringOtherApps])
  let script = """
  tell application "System Events"
    set targetProcess to first application process whose unix id is \(processIdentifier)
    set frontmost of targetProcess to true
    set menuBarItems to menu bar items of menu bar 1 of targetProcess
    if (count of menuBarItems) is 0 then error "The app has no accessible native menu bar items"
    set menuBarTitles to name of every menu bar item of menu bar 1 of targetProcess
    set appMenuTitle to missing value
    set quitMenuName to missing value
    repeat with menuBarItem in menuBarItems
      set candidateTitle to name of menuBarItem
      try
        click menuBarItem
        delay 0.1
        set menuEntries to menu items of menu 1 of menuBarItem
        repeat with menuEntry in menuEntries
          set entryName to name of menuEntry
          if entryName starts with "Quit" then
            set appMenuTitle to candidateTitle
            set quitMenuName to entryName
            click menuEntry
            exit repeat
          end if
        end repeat
      end try
      if quitMenuName is not missing value then exit repeat
    end repeat
    if quitMenuName is missing value then error "No Quit item in native menus for process. Menu bar items: " & (menuBarTitles as string)
    return "Selected " & appMenuTitle & " > " & quitMenuName
  end tell
  """
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = ["-e", script]
  let output = Pipe()
  let errors = Pipe()
  process.standardOutput = output
  process.standardError = errors

  do {
    try process.run()
  } catch {
    throw NSError(domain: "AlulaMacDnd", code: 22, userInfo: [
      NSLocalizedDescriptionKey: "Could not start native menu automation: \(error)"
    ])
  }
  let deadline = Date().addingTimeInterval(8)
  while process.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
  }
  if process.isRunning {
    process.terminate()
    process.waitUntilExit()
    throw NSError(domain: "AlulaMacDnd", code: 23, userInfo: [
      NSLocalizedDescriptionKey: "Native menu automation timed out after 8 seconds"
    ])
  }
  process.waitUntilExit()
  let standardOutput = String(
    data: output.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
  ) ?? ""
  let standardError = String(
    data: errors.fileHandleForReading.readDataToEndOfFile(),
    encoding: .utf8
  ) ?? ""
  guard process.terminationStatus == 0 else {
    throw NSError(domain: "AlulaMacDnd", code: 24, userInfo: [
      NSLocalizedDescriptionKey: "Native menu Quit automation failed (status \(process.terminationStatus)): \(standardError)"
    ])
  }
  print("Selected native menu item Quit Alula Code through System Events.")
  if !standardOutput.isEmpty { print(standardOutput) }
}

func run() throws {
  if CommandLine.arguments.count == 3,
     CommandLine.arguments[1] == "--quit-native-menu"
  {
    guard let processIdentifier = Int32(CommandLine.arguments[2]) else {
      throw NSError(domain: "AlulaMacDnd", code: 25, userInfo: [
        NSLocalizedDescriptionKey: "Native menu Quit requires a numeric process id"
      ])
    }
    try quitThroughNativeMenu(processIdentifier: processIdentifier)
    return
  }

  guard CommandLine.arguments.count == 2 else {
    throw NSError(domain: "AlulaMacDnd", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Usage: macos-native-dnd-input <smoke-dir> | --quit-native-menu <pid>"
    ])
  }

  guard AXIsProcessTrusted() else {
    throw NSError(domain: "AlulaMacDnd", code: 3, userInfo: [
      NSLocalizedDescriptionKey: "Accessibility permission was not granted to this input helper"
    ])
  }

  let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  let ready = directory.appendingPathComponent("ready")
  let deadline = Date().addingTimeInterval(25)
  while !FileManager.default.fileExists(atPath: ready.path), Date() < deadline {
    Thread.sleep(forTimeInterval: 0.1)
  }
  guard FileManager.default.fileExists(atPath: ready.path) else {
    throw NSError(domain: "AlulaMacDnd", code: 4, userInfo: [
      NSLocalizedDescriptionKey: "Flutter integration test did not create its ready marker"
    ])
  }

  guard let app = waitForRunningAlula(deadline: deadline) else {
    throw NSError(domain: "AlulaMacDnd", code: 5, userInfo: [
      NSLocalizedDescriptionKey: "Could not find the running Alula integration-test app"
    ])
  }
  _ = app.activate(options: [])
  let appElement = AXUIElementCreateApplication(app.processIdentifier)
  guard let windows = attribute(appElement, "AXWindows") as? [AXUIElement],
        let window = windows.first else {
    throw NSError(domain: "AlulaMacDnd", code: 6, userInfo: [
      NSLocalizedDescriptionKey: "Alula has no accessible window"
    ])
  }
  let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
  print("AX raise window result: \(raiseResult.rawValue)")
  let focusDeadline = Date().addingTimeInterval(3)
  while Date() < focusDeadline {
    _ = app.activate(options: [])
    let frontmost = attribute(appElement, "AXFrontmost") as? Bool ?? false
    let focused = attribute(window, "AXFocused") as? Bool ?? false
    let main = attribute(window, "AXMain") as? Bool ?? false
    if frontmost && focused && main { break }
    Thread.sleep(forTimeInterval: 0.1)
  }
  logAccessibilityDiagnostics(
    app: app,
    applicationElement: appElement,
    windows: windows
  )

  guard let contentView = children(of: window).first(where: {
    (attribute($0, "AXRole") as? String) == "AXGroup"
  }), let contentFrame = frame(of: contentView) else {
    throw NSError(domain: "AlulaMacDnd", code: 8, userInfo: [
      NSLocalizedDescriptionKey: "Could not locate the Flutter content view frame"
    ])
  }
  let layoutURL = directory.appendingPathComponent("layout.json")
  let layoutData = try Data(contentsOf: layoutURL)
  guard let layout = try JSONSerialization.jsonObject(with: layoutData) as? [String: Any] else {
    throw NSError(domain: "AlulaMacDnd", code: 9, userInfo: [
      NSLocalizedDescriptionKey: "layout.json is not a JSON object"
    ])
  }
  let sourceOffset = try layoutPoint(from: layout, key: "source")
  let targetOffset = try layoutPoint(from: layout, key: "target")
  let devicePixelRatio = layout["devicePixelRatio"] as? Double ?? 1
  guard CGRect(origin: .zero, size: contentFrame.size).contains(sourceOffset),
        CGRect(origin: .zero, size: contentFrame.size).contains(targetOffset) else {
    throw NSError(domain: "AlulaMacDnd", code: 10, userInfo: [
      NSLocalizedDescriptionKey: "Flutter test coordinates are outside the native content view"
    ])
  }

  let source = CGPoint(
    x: contentFrame.minX + sourceOffset.x,
    y: contentFrame.minY + sourceOffset.y
  )
  let target = CGPoint(
    x: contentFrame.minX + targetOffset.x,
    y: contentFrame.minY + targetOffset.y
  )
  print("Alula PID: \(app.processIdentifier)")
  print("Flutter content frame: \(NSStringFromRect(contentFrame)); DPR: \(devicePixelRatio)")
  print("CoreGraphics injection tap: cghidEventTap")
  print("Source local point: \(sourceOffset); screen point: \(source)")
  print("Target local point: \(targetOffset); screen point: \(target)")

  guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
    throw NSError(domain: "AlulaMacDnd", code: 11, userInfo: [
      NSLocalizedDescriptionKey: "Could not create a combined-session event source"
    ])
  }

  let focusedWindowMatches: () -> Bool = {
    guard let focusedWindow = attribute(appElement, "AXFocusedWindow") else {
      return false
    }
    return CFEqual(focusedWindow, window)
  }
  Thread.sleep(forTimeInterval: 0.3)
  var frontmost = attribute(appElement, "AXFrontmost") as? Bool ?? false
  var focused = focusedWindowMatches()
  var main = attribute(window, "AXMain") as? Bool ?? false
  if !(frontmost && focused && main) {
    let windowFrame = frame(of: window) ?? contentFrame
    let titleBarPoint = CGPoint(x: windowFrame.midX, y: windowFrame.minY + 12)
    try postMouseEvent(.mouseMoved, at: titleBarPoint, source: eventSource)
    Thread.sleep(forTimeInterval: 0.1)
    try postMouseEvent(.leftMouseDown, at: titleBarPoint, source: eventSource)
    Thread.sleep(forTimeInterval: 0.1)
    try postMouseEvent(.leftMouseUp, at: titleBarPoint, source: eventSource)
    Thread.sleep(forTimeInterval: 0.3)
    frontmost = attribute(appElement, "AXFrontmost") as? Bool ?? false
    focused = focusedWindowMatches()
    main = attribute(window, "AXMain") as? Bool ?? false
  }
  let windowHasKeyboardFocus = attribute(window, "AXFocused") as? Bool ?? false
  print(
    "After title-bar activation: frontmost=\(frontmost), " +
      "focusedWindowMatches=\(focused), main=\(main), " +
      "windowAXFocused=\(windowHasKeyboardFocus)"
  )
  guard frontmost && focused && main else {
    throw NSError(domain: "AlulaMacDnd", code: 12, userInfo: [
      NSLocalizedDescriptionKey: "App window did not become focused after title-bar activation"
    ])
  }

  let neutralPoint = CGPoint(
    x: (source.x + target.x) / 2,
    y: (source.y + target.y) / 2
  )
  print("Neutral Flutter-area click: \(neutralPoint)")
  try postMouseEvent(.mouseMoved, at: neutralPoint, source: eventSource)
  Thread.sleep(forTimeInterval: 0.1)
  try postMouseEvent(.leftMouseDown, at: neutralPoint, source: eventSource)
  Thread.sleep(forTimeInterval: 0.1)
  try postMouseEvent(.leftMouseUp, at: neutralPoint, source: eventSource)
  Thread.sleep(forTimeInterval: 0.5)
  print("System Events neutral click: \(clickWithSystemEvents(at: neutralPoint))")
  Thread.sleep(forTimeInterval: 0.5)
  let pointerEventsURL = directory.appendingPathComponent("pointer-events.jsonl")
  let previousPointerEvents =
    (try? String(contentsOf: pointerEventsURL, encoding: .utf8)) ?? ""
  try postMouseEvent(
    .mouseMoved,
    at: neutralPoint,
    source: eventSource,
    targetPID: app.processIdentifier
  )
  Thread.sleep(forTimeInterval: 0.5)
  let pointerEventsAfterTargetedMove =
    (try? String(contentsOf: pointerEventsURL, encoding: .utf8)) ?? ""
  let processTargetedInputRouted =
    pointerEventsAfterTargetedMove.count > previousPointerEvents.count
  print("CGEventPostToPid pointer route: \(processTargetedInputRouted)")
  if !pointerEventsAfterTargetedMove.isEmpty {
    print(
      "Flutter pointer events after neutral click:\n\(pointerEventsAfterTargetedMove)"
    )
  } else {
    print("Flutter pointer events after neutral click: <none>")
  }

  let dragTargetPID = processTargetedInputRouted ? app.processIdentifier : nil
  try postMouseEvent(
    .mouseMoved,
    at: source,
    source: eventSource,
    targetPID: dragTargetPID
  )
  Thread.sleep(forTimeInterval: 0.3)
  try postMouseEvent(
    .leftMouseDown,
    at: source,
    source: eventSource,
    targetPID: dragTargetPID
  )
  Thread.sleep(forTimeInterval: 0.2)
  for step in 1...24 {
    let progress = CGFloat(step) / 24
    let point = CGPoint(
      x: source.x + (target.x - source.x) * progress,
      y: source.y + (target.y - source.y) * progress
    )
    try postMouseEvent(
      .leftMouseDragged,
      at: point,
      source: eventSource,
      targetPID: dragTargetPID
    )
    Thread.sleep(forTimeInterval: 0.04)
  }
  Thread.sleep(forTimeInterval: 0.5)
  try postMouseEvent(
    .leftMouseUp,
    at: target,
    source: eventSource,
    targetPID: dragTargetPID
  )
  print("AppKit mouse location after drag: \(NSEvent.mouseLocation)")
  let postingMechanism =
    dragTargetPID == nil ? "cghidEventTap" : "CGEventPostToPid"
  print(
    "Posted native mouse drag from Flutter source to target coordinates " +
      "using \(postingMechanism)"
  )
}

do {
  try run()
} catch {
  fputs("macOS native DnD input failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
