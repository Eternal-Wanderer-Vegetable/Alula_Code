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

func isNativeQuitMenuItem(_ element: AXUIElement) -> Bool {
  if labels(of: element).contains(where: { $0.lowercased().hasPrefix("quit") }) {
    return true
  }

  // macOS localizes the visible Quit title. Command-Q is the stable menu
  // identity across locales; AX reports the primary key and modifier mask.
  guard
    let commandCharacter = attribute(
      element,
      kAXMenuItemCmdCharAttribute as String
    ) as? String,
    commandCharacter.lowercased() == "q",
    let rawModifiers = attribute(
      element,
      kAXMenuItemCmdModifiersAttribute as String
    ) as? NSNumber
  else {
    return false
  }

  // AXMenuItemCmdModifiers represents modifiers other than Command. A zero
  // mask therefore identifies the standard Command-Q application menu item.
  return rawModifiers.uint32Value == 0
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

func quitThroughAccessibilityMenu(processIdentifier: pid_t) throws {
  let applicationElement = AXUIElementCreateApplication(processIdentifier)
  _ = AXUIElementSetMessagingTimeout(applicationElement, 2.0)
  var menuBarElement: AXUIElement?
  var lastMenuBarError: AXError = .noValue
  let menuBarDeadline = Date().addingTimeInterval(15)
  while Date() < menuBarDeadline {
    var rawMenuBar: CFTypeRef?
    lastMenuBarError = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXMenuBarAttribute as CFString,
      &rawMenuBar
    )
    if lastMenuBarError == .success,
       let rawMenuBar,
       CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID()
    {
      menuBarElement = unsafeBitCast(rawMenuBar, to: AXUIElement.self)
      if menuBarElement != nil { break }
    }
    Thread.sleep(forTimeInterval: 0.25)
  }
  guard let menuBarElement else {
    throw NSError(domain: "AlulaMacDnd", code: 22, userInfo: [
      NSLocalizedDescriptionKey:
        "Could not read the native menu bar through Accessibility (AXError \(lastMenuBarError.rawValue))"
    ])
  }

  func descendants(of element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 5 else { return [] }
    _ = AXUIElementSetMessagingTimeout(element, 2.0)
    let directChildren = children(of: element)
    return directChildren + directChildren.flatMap {
      descendants(of: $0, depth: depth + 1)
    }
  }

  _ = AXUIElementSetMessagingTimeout(menuBarElement, 2.0)
  let menuBarItems = children(of: menuBarElement)
  var menuBarTitles: [String] = []
  for menuBarItem in menuBarItems {
    _ = AXUIElementSetMessagingTimeout(menuBarItem, 2.0)
    let candidateTitle = labels(of: menuBarItem).first ?? "<unnamed>"
    menuBarTitles.append(candidateTitle)
    let pressResult = AXUIElementPerformAction(menuBarItem, "AXPress" as CFString)
    guard pressResult == .success else { continue }

    var menuEntries: [AXUIElement] = []
    for _ in 0..<10 {
      menuEntries = descendants(of: menuBarItem)
      if !menuEntries.isEmpty { break }
      Thread.sleep(forTimeInterval: 0.1)
    }
    for menuEntry in menuEntries {
      _ = AXUIElementSetMessagingTimeout(menuEntry, 2.0)
      guard isNativeQuitMenuItem(menuEntry) else { continue }
      let quitResult = AXUIElementPerformAction(menuEntry, "AXPress" as CFString)
      guard quitResult == .success else { continue }
      let entryName = labels(of: menuEntry).first ?? "Command-Q menu item"
      print("Selected native menu item \(candidateTitle) > \(entryName) through Accessibility API.")
      return
    }
  }

  throw NSError(domain: "AlulaMacDnd", code: 23, userInfo: [
    NSLocalizedDescriptionKey:
      "No accessible Quit item in native menus. Menu bar items: \(menuBarTitles.joined(separator: ", "))"
  ])
}

func quitThroughSystemEvents(processIdentifier: pid_t) throws -> String {
  let script = """
  tell application "System Events"
    set targetProcess to first application process whose unix id is \(processIdentifier)
    set frontmost of targetProcess to true
    set menuBarItems to menu bar items of menu bar 1 of targetProcess
    set menuBarTitles to {}
    set appMenuTitle to missing value
    set quitMenuName to missing value
    repeat with menuBarItem in menuBarItems
      try
        set candidateTitle to name of menuBarItem
        set end of menuBarTitles to candidateTitle
        click menuBarItem
        delay 0.1
        set menuEntries to menu items of menu 1 of menuBarItem
        repeat with menuEntry in menuEntries
          try
            set entryName to name of menuEntry
            set isQuitMenuItem to entryName starts with "Quit"
            try
              set shortcutCharacter to value of attribute "AXMenuItemCmdChar" of menuEntry
              set shortcutModifiers to value of attribute "AXMenuItemCmdModifiers" of menuEntry
              if (shortcutCharacter is "q" or shortcutCharacter is "Q") and shortcutModifiers is 0 then
                set isQuitMenuItem to true
              end if
            end try
            if isQuitMenuItem then
              set appMenuTitle to candidateTitle
              set quitMenuName to entryName
              click menuEntry
              exit repeat
            end if
          end try
        end repeat
      end try
      if quitMenuName is not missing value then exit repeat
    end repeat
    if quitMenuName is missing value then
      error "No Quit item in native menus. Menu bar items: " & (menuBarTitles as string)
    end if
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
    throw NSError(domain: "AlulaMacDnd", code: 26, userInfo: [
      NSLocalizedDescriptionKey: "Could not start the System Events Quit fallback: \(error)"
    ])
  }

  let deadline = Date().addingTimeInterval(20)
  while process.isRunning && Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
  }
  if process.isRunning {
    process.terminate()
    let terminateDeadline = Date().addingTimeInterval(2)
    while process.isRunning && Date() < terminateDeadline {
      Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
      _ = kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
    throw NSError(domain: "AlulaMacDnd", code: 27, userInfo: [
      NSLocalizedDescriptionKey: "System Events Quit fallback timed out after 20 seconds"
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
    throw NSError(domain: "AlulaMacDnd", code: 28, userInfo: [
      NSLocalizedDescriptionKey:
        "System Events Quit fallback failed (status \(process.terminationStatus)): \(standardError)"
    ])
  }
  return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
}

func quitThroughNativeMenu(
  bundleIdentifier: String,
  expectedBundlePath: String
) throws {
  guard AXIsProcessTrusted() else {
    throw NSError(domain: "AlulaMacDnd", code: 20, userInfo: [
      NSLocalizedDescriptionKey: "Accessibility permission was not granted to this input helper"
    ])
  }
  let expectedBundleURL = URL(fileURLWithPath: expectedBundlePath)
    .standardizedFileURL.resolvingSymlinksInPath()
  func isExpectedApplication(_ candidate: NSRunningApplication) -> Bool {
    guard !candidate.isTerminated,
          candidate.bundleIdentifier == bundleIdentifier,
          let bundleURL = candidate.bundleURL else {
      return false
    }
    return bundleURL.standardizedFileURL.resolvingSymlinksInPath().path ==
      expectedBundleURL.path
  }

  let appDiscoveryDeadline = Date().addingTimeInterval(15)
  var app = NSRunningApplication.runningApplications(
    withBundleIdentifier: bundleIdentifier
  ).last(where: isExpectedApplication)
  while app == nil && Date() < appDiscoveryDeadline {
    Thread.sleep(forTimeInterval: 0.1)
    app = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    ).last(where: isExpectedApplication)
  }
  guard let app else {
    throw NSError(domain: "AlulaMacDnd", code: 21, userInfo: [
      NSLocalizedDescriptionKey:
        "Could not find a running app with bundle identifier \(bundleIdentifier) at \(expectedBundleURL.path)"
    ])
  }

  let processIdentifier = app.processIdentifier
  print(
    "Targeting native Quit menu in \(app.localizedName ?? bundleIdentifier) " +
      "at \(expectedBundleURL.path) (pid \(processIdentifier), active=\(app.isActive))."
  )
  let activationAccepted = app.activate(options: [.activateIgnoringOtherApps])
  let activationDeadline = Date().addingTimeInterval(8)
  while !app.isActive && Date() < activationDeadline {
    Thread.sleep(forTimeInterval: 0.1)
  }
  if app.isActive {
    print("Target app is active; selecting its native Quit menu.")
  } else {
    let frontmost = NSWorkspace.shared.frontmostApplication
    print(
      "NSRunningApplication activation did not foreground the target " +
        "(accepted=\(activationAccepted), frontmost=\(frontmost?.localizedName ?? "<none>"), " +
        "frontmostPID=\(frontmost?.processIdentifier ?? 0)); " +
        "continuing with PID-targeted native menu access."
    )
  }
  do {
    try quitThroughAccessibilityMenu(processIdentifier: processIdentifier)
  } catch let accessibilityError {
    print(
      "Accessibility API could not select Quit; trying System Events: \(accessibilityError.localizedDescription)"
    )
    do {
      let result = try quitThroughSystemEvents(processIdentifier: processIdentifier)
      print("Selected native menu item \(result) through System Events.")
    } catch let systemEventsError {
      throw NSError(domain: "AlulaMacDnd", code: 29, userInfo: [
        NSLocalizedDescriptionKey:
          "Accessibility API Quit probe failed (\(accessibilityError.localizedDescription)); System Events fallback failed (\(systemEventsError.localizedDescription))"
      ])
    }
  }
}

func run() throws {
  if CommandLine.arguments.count == 4,
     CommandLine.arguments[1] == "--quit-native-menu"
  {
    let bundleIdentifier = CommandLine.arguments[2]
    let bundlePath = CommandLine.arguments[3]
    guard !bundleIdentifier.isEmpty, !bundlePath.isEmpty else {
      throw NSError(domain: "AlulaMacDnd", code: 25, userInfo: [
        NSLocalizedDescriptionKey: "Native menu Quit requires an app bundle identifier and bundle path"
      ])
    }
    try quitThroughNativeMenu(
      bundleIdentifier: bundleIdentifier,
      expectedBundlePath: bundlePath
    )
    return
  }

  guard CommandLine.arguments.count == 2 else {
    throw NSError(domain: "AlulaMacDnd", code: 1, userInfo: [
      NSLocalizedDescriptionKey:
        "Usage: macos-native-dnd-input <smoke-dir> | --quit-native-menu <bundle-id> <app-bundle-path>"
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
