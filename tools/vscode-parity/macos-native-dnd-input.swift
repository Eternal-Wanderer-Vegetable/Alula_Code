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

func findElement(
  in root: AXUIElement,
  matching needle: String,
  depth: Int = 0,
  visited: inout Int
) -> AXUIElement? {
  guard depth < 24, visited < 20_000 else { return nil }
  visited += 1
  if labels(of: root).contains(where: { $0.localizedCaseInsensitiveContains(needle) }) {
    return root
  }
  for child in children(of: root) {
    if let result = findElement(
      in: child,
      matching: needle,
      depth: depth + 1,
      visited: &visited
    ) {
      return result
    }
  }
  return nil
}

func postMouseEvent(_ type: CGEventType, at point: CGPoint) throws {
  guard
    let event = CGEvent(
      mouseEventSource: nil,
      mouseType: type,
      mouseCursorPosition: point,
      mouseButton: .left
    )
  else {
    throw NSError(domain: "AlulaMacDnd", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Could not construct CoreGraphics mouse event"
    ])
  }
  event.post(tap: .cghidEventTap)
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

func waitForAnchor(
  appElement: AXUIElement,
  needle: String,
  deadline: Date
) -> (AXUIElement, CGRect)? {
  while Date() < deadline {
    var visited = 0
    if let element = findElement(
      in: appElement,
      matching: needle,
      visited: &visited
    ), let elementFrame = frame(of: element), !elementFrame.isEmpty {
      return (element, elementFrame)
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
    print(
      "AX \(label): pid=\(pid) pidStatus=\(pidResult.rawValue), " +
        "attributesStatus=\(namesResult.rawValue), attributes=\(attributes), " +
        "childrenStatus=\(childrenResult.rawValue), childCount=\(String(describing: childCount)), " +
        "labels=\(labels(of: element)), frame=\(frame(of: element).map(NSStringFromRect) ?? "<no-frame>")"
    )
  }

  describe("application", applicationElement)
  for (index, window) in windows.enumerated() {
    describe("window[\(index)]", window)
  }

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

func run() throws {
  guard CommandLine.arguments.count == 2 else {
    throw NSError(domain: "AlulaMacDnd", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "Usage: macos-native-dnd-input <smoke-dir>"
    ])
  }

  guard AXIsProcessTrusted() else {
    throw NSError(domain: "AlulaMacDnd", code: 3, userInfo: [
      NSLocalizedDescriptionKey: "Accessibility permission was not granted to this input helper"
    ])
  }

  let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
  let ready = directory.appendingPathComponent("ready")
  let deadline = Date().addingTimeInterval(50)
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
  logAccessibilityDiagnostics(
    app: app,
    applicationElement: appElement,
    windows: windows
  )

  guard let (_, sourceFrame) = waitForAnchor(
    appElement: window,
    needle: "alula-dnd-source",
    deadline: deadline
  ) else {
    var visited = 0
    func dump(_ element: AXUIElement, depth: Int) {
      guard depth < 8, visited < 300 else { return }
      visited += 1
      let bounds = frame(of: element).map(NSStringFromRect) ?? "<no-frame>"
      let indentation = String(repeating: " ", count: depth * 2)
      print("AX \(indentation)\(labels(of: element)) \(bounds)")
      for child in children(of: element) { dump(child, depth: depth + 1) }
    }
    dump(window, depth: 0)
    throw NSError(domain: "AlulaMacDnd", code: 7, userInfo: [
      NSLocalizedDescriptionKey: "Could not locate AX source anchor"
    ])
  }
  guard let (_, targetFrame) = waitForAnchor(
    appElement: window,
    needle: "alula-dnd-target",
    deadline: deadline
  ) else {
    throw NSError(domain: "AlulaMacDnd", code: 8, userInfo: [
      NSLocalizedDescriptionKey: "Could not locate AX target anchor"
    ])
  }

  let source = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
  let target = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
  print("Alula PID: \(app.processIdentifier)")
  print("Source AX frame: \(NSStringFromRect(sourceFrame)); point: \(source)")
  print("Target AX frame: \(NSStringFromRect(targetFrame)); point: \(target)")

  try postMouseEvent(.mouseMoved, at: source)
  Thread.sleep(forTimeInterval: 0.3)
  try postMouseEvent(.leftMouseDown, at: source)
  Thread.sleep(forTimeInterval: 0.2)
  for step in 1...24 {
    let progress = CGFloat(step) / 24
    let point = CGPoint(
      x: source.x + (target.x - source.x) * progress,
      y: source.y + (target.y - source.y) * progress
    )
    try postMouseEvent(.leftMouseDragged, at: point)
    Thread.sleep(forTimeInterval: 0.04)
  }
  Thread.sleep(forTimeInterval: 0.5)
  try postMouseEvent(.leftMouseUp, at: target)
  print("Posted native mouse drag from source anchor to target anchor")
}

do {
  try run()
} catch {
  fputs("macOS native DnD input failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
