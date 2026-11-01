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
  to processIdentifier: pid_t
) throws {
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
  event.postToPid(processIdentifier)
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
  print("Source local point: \(sourceOffset); screen point: \(source)")
  print("Target local point: \(targetOffset); screen point: \(target)")

  try postMouseEvent(.mouseMoved, at: source, to: app.processIdentifier)
  Thread.sleep(forTimeInterval: 0.3)
  try postMouseEvent(.leftMouseDown, at: source, to: app.processIdentifier)
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
      to: app.processIdentifier
    )
    Thread.sleep(forTimeInterval: 0.04)
  }
  Thread.sleep(forTimeInterval: 0.5)
  try postMouseEvent(.leftMouseUp, at: target, to: app.processIdentifier)
  print("AppKit mouse location after drag: \(NSEvent.mouseLocation)")
  print("Posted native mouse drag from Flutter source to target coordinates")
}

do {
  try run()
} catch {
  fputs("macOS native DnD input failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
