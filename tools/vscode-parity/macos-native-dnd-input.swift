import AppKit
import ApplicationServices
import Carbon.HIToolbox
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

func nativeQuitMatchReason(_ element: AXUIElement) -> String? {
  // Preserve the original attribute order and prefix/shortcut matching rules.
  for name in ["AXIdentifier", "AXLabel", "AXDescription", "AXTitle", "AXValue"] {
    if let value = attribute(element, name) as? String,
       value.lowercased().hasPrefix("quit") {
      return "\(name).lowercased.hasPrefix(quit)"
    }
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
    return nil
  }

  // AXMenuItemCmdModifiers represents modifiers other than Command. A zero
  // mask therefore identifies the standard Command-Q application menu item.
  return rawModifiers.uint32Value == 0 ? "AXMenuItemCmdChar=q and AXMenuItemCmdModifiers=0" : nil
}

func isNativeQuitMenuItem(_ element: AXUIElement) -> Bool {
  nativeQuitMatchReason(element) != nil
}

func nativeDiagnostic(_ stage: String, _ fields: [String: Any] = [:]) {
  var record = fields
  record["stage"] = stage
  record["timestamp"] = ISO8601DateFormatter().string(from: Date())
  if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data([10]))
  }
}

func nativeError(_ message: String) -> NSError {
  NSError(domain: "AlulaMacDnd", code: 31, userInfo: [NSLocalizedDescriptionKey: message])
}

func canonicalPath(_ path: String) -> String {
  URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
}

struct NativeAppIdentity: Codable, Equatable {
  let pid: pid_t
  let launchDate: Date
  let bundleIdentifier: String
  let bundlePath: String
  let executablePath: String

  init(_ app: NSRunningApplication) throws {
    guard app.processIdentifier > 0, !app.isTerminated,
          let launchDate = app.launchDate,
          let bundleIdentifier = app.bundleIdentifier,
          let bundleURL = app.bundleURL, let executableURL = app.executableURL else {
      throw nativeError("Unknown native application identity")
    }
    self.pid = app.processIdentifier
    self.launchDate = launchDate
    self.bundleIdentifier = bundleIdentifier
    self.bundlePath = canonicalPath(bundleURL.path)
    self.executablePath = canonicalPath(executableURL.path)
  }

  func validate() throws {
    guard pid > 0, launchDate.timeIntervalSinceReferenceDate.isFinite,
          !bundleIdentifier.isEmpty, bundlePath.hasPrefix("/"),
          bundlePath == canonicalPath(bundlePath), executablePath == canonicalPath(executablePath),
          executablePath.hasPrefix(bundlePath + "/Contents/MacOS/") else {
      throw nativeError("Invalid bound native application identity")
    }
  }

  func liveApplication() throws -> NSRunningApplication {
    try validate()
    guard let app = NSRunningApplication(processIdentifier: pid),
          try NativeAppIdentity(app) == self else {
      throw nativeError("Bound native application identity changed or is unavailable (pid \(pid))")
    }
    return app
  }

  func state() -> String {
    guard (try? validate()) != nil else { return "unknown" }
    if kill(pid, 0) != 0 { return errno == ESRCH ? "gone" : "unknown" }
    return (try? liveApplication()) != nil ? "alive" : "unknown"
  }
}

struct NativeAppSnapshot: Codable {
  let capturedAt: Date
  let bundleIdentifier: String
  let bundlePath: String
  let applications: [NativeAppIdentity]
}

func matchingNativeApps(_ bundleIdentifier: String, _ bundlePath: String) throws -> [NativeAppIdentity] {
  try NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
    .filter { !$0.isTerminated && $0.bundleURL.map { canonicalPath($0.path) } == bundlePath }
    .map { try NativeAppIdentity($0) }
}

func readNativeJSON<T: Decodable>(_ path: String, as type: T.Type) throws -> T {
  try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func writeNativeJSON<T: Encodable>(_ value: T, to path: String) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  try encoder.encode(value).write(to: URL(fileURLWithPath: path), options: .atomic)
}

func bindNativeApp(_ bundleIdentifier: String, _ bundlePath: String, beforePath: String) throws -> NativeAppIdentity {
  let before = try readNativeJSON(beforePath, as: NativeAppSnapshot.self)
  guard before.bundleIdentifier == bundleIdentifier, before.bundlePath == bundlePath,
        before.capturedAt <= Date() else { throw nativeError("Native snapshot target mismatch") }
  for identity in before.applications {
    try identity.validate()
    guard identity.bundleIdentifier == bundleIdentifier, identity.bundlePath == bundlePath else {
      throw nativeError("Native snapshot contains an unexpected application")
    }
  }
  let deadline = ProcessInfo.processInfo.systemUptime + 15
  repeat {
    let candidates = try matchingNativeApps(bundleIdentifier, bundlePath)
      .filter { !before.applications.contains($0) }
    nativeDiagnostic("binding", ["newCandidates": candidates.map { $0.pid }])
    guard candidates.count <= 1 else { throw nativeError("Multiple new native application instances") }
    if let target = candidates.first {
      try target.validate()
      guard target.launchDate >= before.capturedAt else {
        throw nativeError("Native candidate predates the prelaunch snapshot")
      }
      _ = try target.liveApplication()
      return target
    }
    Thread.sleep(forTimeInterval: min(0.1, max(0, deadline - ProcessInfo.processInfo.systemUptime)))
  } while ProcessInfo.processInfo.systemUptime < deadline
  throw nativeError("No new native application instance within the existing 15-second discovery budget")
}

func observeNativeApp(_ target: NativeAppIdentity, openPID: pid_t? = nil, windows: Bool = false) throws {
  try target.validate()
  let deadline = ProcessInfo.processInfo.systemUptime + (openPID == nil ? 0 : 20)
  var previous = ""
  repeat {
    let appState = target.state()
    let openState: String
    if let openPID {
      openState = kill(openPID, 0) == 0 ? "alive" : (errno == ESRCH ? "gone" : "unknown")
    } else { openState = "unobserved" }
    let state = "\(appState)/\(openState)"
    if state != previous {
      nativeDiagnostic("state-transition", ["appPID": target.pid, "appState": appState,
        "openPID": openPID ?? 0, "openState": openState])
      previous = state
    }
    if windows, appState == "alive" {
      // CGWindow summaries avoid a recursive/possibly blocked AX walk during failure cleanup.
      _ = try target.liveApplication()
      let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
      let owned = infos.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == target.pid }
      nativeDiagnostic("pre-cleanup-windows", ["pid": target.pid, "count": owned.count,
        "windows": Array(owned.prefix(20))])
    }
    let now = ProcessInfo.processInfo.systemUptime
    if openPID == nil || appState == "unknown" || openState == "unknown" ||
       (appState == "gone" && openState == "gone") || now >= deadline {
      nativeDiagnostic("final-state", ["appPID": target.pid, "appState": appState,
        "openPID": openPID ?? 0, "openState": openState])
      print(appState)
      if appState == "unknown" || (openPID != nil &&
          (appState != "gone" || openState != "gone" || now > deadline)) {
        throw nativeError("Native Quit observation failed: app=\(appState), open=\(openState) (20-second limit)")
      }
      return
    }
    Thread.sleep(forTimeInterval: min(0.25, max(0, deadline - now)))
  } while true
}

func logNativeAX(_ stage: String, _ element: AXUIElement, indices: [String: Any]) {
  var fields = indices
  for name in ["AXIdentifier", "AXTitle", "AXDescription", "AXLabel", "AXValue",
               "AXRole", "AXSubrole", "AXEnabled", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers"] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    fields[name] = ["status": result.rawValue,
      "value": value.map { String(describing: $0) } ?? "<unavailable>"] as [String: Any]
  }
  nativeDiagnostic(stage, fields)
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

func quitThroughAccessibilityMenu(processIdentifier: pid_t, validateTarget: () throws -> Void) throws {
  nativeDiagnostic("ax-menu-start", ["pid": processIdentifier])
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
  for (parentIndex, menuBarItem) in menuBarItems.enumerated() {
    _ = AXUIElementSetMessagingTimeout(menuBarItem, 2.0)
    let candidateTitle = labels(of: menuBarItem).first ?? "<unnamed>"
    menuBarTitles.append(candidateTitle)
    logNativeAX("ax-parent-before-press", menuBarItem, indices: ["parentIndex": parentIndex])
    try validateTarget()
    let pressResult = AXUIElementPerformAction(menuBarItem, "AXPress" as CFString)
    nativeDiagnostic("ax-parent-press-result", ["parentIndex": parentIndex, "result": pressResult.rawValue])
    guard pressResult == .success else { continue }

    var menuEntries: [AXUIElement] = []
    for _ in 0..<10 {
      menuEntries = descendants(of: menuBarItem)
      if !menuEntries.isEmpty { break }
      Thread.sleep(forTimeInterval: 0.1)
    }
    for (entryIndex, menuEntry) in menuEntries.enumerated() {
      _ = AXUIElementSetMessagingTimeout(menuEntry, 2.0)
      guard let matchReason = nativeQuitMatchReason(menuEntry) else { continue }
      logNativeAX("ax-quit-before-press", menuEntry, indices: [
        "parentIndex": parentIndex, "entryIndex": entryIndex, "matchReason": matchReason,
      ])
      try validateTarget()
      let quitResult = AXUIElementPerformAction(menuEntry, "AXPress" as CFString)
      nativeDiagnostic("ax-quit-press-result", ["parentIndex": parentIndex,
        "entryIndex": entryIndex, "result": quitResult.rawValue])
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
    set parentIndex to 0
    repeat with menuBarItem in menuBarItems
      set parentIndex to parentIndex + 1
      try
        set candidateTitle to name of menuBarItem
        set end of menuBarTitles to candidateTitle
        click menuBarItem
        delay 0.1
        set menuEntries to menu items of menu 1 of menuBarItem
        set entryIndex to 0
        repeat with menuEntry in menuEntries
          set entryIndex to entryIndex + 1
          try
            set entryName to name of menuEntry
            set isQuitMenuItem to entryName starts with "Quit"
            set matchReason to "name starts with Quit"
            try
              set shortcutCharacter to value of attribute "AXMenuItemCmdChar" of menuEntry
              set shortcutModifiers to value of attribute "AXMenuItemCmdModifiers" of menuEntry
              if (shortcutCharacter is "q" or shortcutCharacter is "Q") and shortcutModifiers is 0 then
                if not isQuitMenuItem then set matchReason to "AXMenuItemCmdChar=q and AXMenuItemCmdModifiers=0"
                set isQuitMenuItem to true
              end if
            end try
            if isQuitMenuItem then
              set appMenuTitle to candidateTitle
              set quitMenuName to entryName
              log ((current date) as string) & " SystemEvents before-click parentIndex=" & parentIndex & " entryIndex=" & entryIndex & " matchReason=" & matchReason
              repeat with attributeName in {"AXIdentifier", "AXTitle", "AXDescription", "AXLabel", "AXValue", "AXRole", "AXSubrole", "AXEnabled", "AXMenuItemCmdChar", "AXMenuItemCmdModifiers"}
                try
                  set attributeValue to value of attribute (contents of attributeName) of menuEntry
                  log (contents of attributeName) & "=" & (attributeValue as string)
                on error attributeError
                  log (contents of attributeName) & "=<unavailable: " & attributeError & ">"
                end try
              end repeat
              click menuEntry
              log ((current date) as string) & " SystemEvents click-result=success"
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
  process.standardOutput = output
  // Stream timestamped pre-click evidence even if osascript later times out.
  process.standardError = FileHandle.standardError

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
  nativeDiagnostic("system-events-result", ["status": process.terminationStatus])
  guard process.terminationStatus == 0 else {
    throw NSError(domain: "AlulaMacDnd", code: 28, userInfo: [
      NSLocalizedDescriptionKey:
        "System Events Quit fallback failed (status \(process.terminationStatus)); see streamed stderr"
    ])
  }
  return standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
}

func postCommandQ(to processIdentifier: pid_t) throws {
  guard
    let source = CGEventSource(stateID: .hidSystemState),
    let commandDown = CGEvent(
      keyboardEventSource: source,
      virtualKey: CGKeyCode(kVK_Command),
      keyDown: true
    ),
    let keyDown = CGEvent(
      keyboardEventSource: source,
      virtualKey: CGKeyCode(kVK_ANSI_Q),
      keyDown: true
    ),
    let keyUp = CGEvent(
      keyboardEventSource: source,
      virtualKey: CGKeyCode(kVK_ANSI_Q),
      keyDown: false
    ),
    let commandUp = CGEvent(
      keyboardEventSource: source,
      virtualKey: CGKeyCode(kVK_Command),
      keyDown: false
    )
  else {
    throw NSError(domain: "AlulaMacDnd", code: 30, userInfo: [
      NSLocalizedDescriptionKey: "Could not create the native Command-Q keyboard events"
    ])
  }

  commandDown.flags = .maskCommand
  keyDown.flags = .maskCommand
  keyUp.flags = .maskCommand
  commandUp.flags = []
  commandDown.postToPid(processIdentifier)
  Thread.sleep(forTimeInterval: 0.02)
  keyDown.postToPid(processIdentifier)
  Thread.sleep(forTimeInterval: 0.05)
  keyUp.postToPid(processIdentifier)
  Thread.sleep(forTimeInterval: 0.02)
  commandUp.postToPid(processIdentifier)
  print(
    "Posted the native Command-Q menu shortcut to pid \(processIdentifier); " +
      "the Availability step will verify app termination."
  )
}

func quitThroughNativeMenu(
  bundleIdentifier: String,
  expectedBundlePath: String,
  targetPath: String? = nil
) throws {
  guard AXIsProcessTrusted() else {
    throw NSError(domain: "AlulaMacDnd", code: 20, userInfo: [
      NSLocalizedDescriptionKey: "Accessibility permission was not granted to this input helper"
    ])
  }
  let expectedBundleURL = URL(fileURLWithPath: canonicalPath(expectedBundlePath))
  let target: NativeAppIdentity
  if let targetPath {
    target = try readNativeJSON(targetPath, as: NativeAppIdentity.self)
  } else {
    // Legacy manual invocation remains supported, but ambiguity must fail.
    let deadline = ProcessInfo.processInfo.systemUptime + 15
    var candidates = try matchingNativeApps(bundleIdentifier, expectedBundleURL.path)
    while candidates.isEmpty && ProcessInfo.processInfo.systemUptime < deadline {
      Thread.sleep(forTimeInterval: 0.1)
      candidates = try matchingNativeApps(bundleIdentifier, expectedBundleURL.path)
    }
    guard candidates.count == 1 else { throw nativeError("Native Quit needs exactly one target instance") }
    target = candidates[0]
  }
  try target.validate()
  guard target.bundleIdentifier == bundleIdentifier, target.bundlePath == expectedBundleURL.path else {
    throw nativeError("Native Quit bound target does not match requested bundle identifier/path")
  }
  let app = try target.liveApplication()
  let validateTarget = { _ = try target.liveApplication() }
  nativeDiagnostic("quit-target-validated", ["pid": target.pid, "bundlePath": target.bundlePath,
    "launchDate": target.launchDate.timeIntervalSince1970, "executablePath": target.executablePath])
  let processIdentifier = target.pid
  print(
    "Targeting native Quit menu in \(app.localizedName ?? bundleIdentifier) " +
      "at \(expectedBundleURL.path) (pid \(processIdentifier), active=\(app.isActive))."
  )
  nativeDiagnostic("activation-start", ["pid": processIdentifier])
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
    try validateTarget()
    try quitThroughAccessibilityMenu(processIdentifier: processIdentifier, validateTarget: validateTarget)
    nativeDiagnostic("ax-selection-completed", ["pid": processIdentifier])
  } catch let accessibilityError {
    nativeDiagnostic("ax-fallback", ["error": accessibilityError.localizedDescription])
    print(
      "Accessibility API could not select Quit; trying System Events: \(accessibilityError.localizedDescription)"
    )
    do {
      try validateTarget()
      nativeDiagnostic("system-events-start", ["pid": processIdentifier])
      let result = try quitThroughSystemEvents(processIdentifier: processIdentifier)
      print("Selected native menu item \(result) through System Events.")
    } catch let systemEventsError {
      nativeDiagnostic("command-q-fallback", ["error": systemEventsError.localizedDescription])
      print(
        "Native menu labels/shortcut metadata were unavailable to Accessibility and " +
          "System Events; dispatching the app's native Command-Q menu shortcut. " +
          "Accessibility: \(accessibilityError.localizedDescription); " +
          "System Events: \(systemEventsError.localizedDescription)"
      )
      try validateTarget()
      nativeDiagnostic("command-q-before-post", ["pid": processIdentifier])
      try postCommandQ(to: processIdentifier)
      nativeDiagnostic("command-q-posted", ["pid": processIdentifier, "deliveryAcknowledged": false])
    }
  }
}

func run() throws {
  let args = CommandLine.arguments
  if args.count == 5, args[1] == "--snapshot-native-apps" {
    let path = canonicalPath(args[3])
    guard !args[2].isEmpty else { throw nativeError("Snapshot requires a bundle identifier") }
    let snapshot = NativeAppSnapshot(capturedAt: Date(), bundleIdentifier: args[2],
      bundlePath: path, applications: try matchingNativeApps(args[2], path))
    try writeNativeJSON(snapshot, to: args[4])
    nativeDiagnostic("prelaunch-snapshot", ["pids": snapshot.applications.map { $0.pid }, "path": path])
    return
  }
  if args.count == 6, args[1] == "--bind-native-app" {
    let target = try bindNativeApp(args[2], canonicalPath(args[3]), beforePath: args[4])
    try writeNativeJSON(target, to: args[5])
    nativeDiagnostic("bound-target", ["pid": target.pid, "bundlePath": target.bundlePath,
      "launchDate": target.launchDate.timeIntervalSince1970, "executablePath": target.executablePath])
    print(target.pid) // stdout is only the numeric PID, never diagnostic text.
    return
  }
  if (args.count == 3 || args.count == 4), args[1] == "--observe-native-app" {
    let target = try readNativeJSON(args[2], as: NativeAppIdentity.self)
    if args.count == 4, args[3] != "--windows" {
      guard let openPID = pid_t(args[3]), openPID > 0, openPID != target.pid else {
        throw nativeError("Observation requires a distinct positive open-W wrapper PID")
      }
      try observeNativeApp(target, openPID: openPID)
    } else {
      try observeNativeApp(target, windows: args.count == 4)
    }
    return
  }
  if args.count == 3, args[1] == "--validate-native-app" {
    let target = try readNativeJSON(args[2], as: NativeAppIdentity.self)
    _ = try target.liveApplication()
    print(target.pid)
    return
  }
  if (CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5),
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
      expectedBundlePath: bundlePath,
      targetPath: args.count == 5 ? args[4] : nil
    )
    return
  }

  guard CommandLine.arguments.count == 2 else {
    throw NSError(domain: "AlulaMacDnd", code: 1, userInfo: [
      NSLocalizedDescriptionKey:
        "Usage: macos-native-dnd-input <smoke-dir> | --quit-native-menu <bundle-id> <app-bundle-path> [target.json] | " +
          "--snapshot-native-apps <bundle-id> <app-bundle-path> <before.json> | " +
          "--bind-native-app <bundle-id> <app-bundle-path> <before.json> <target.json> | " +
          "--observe-native-app <target.json> [open-pid|--windows] | --validate-native-app <target.json>"
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
