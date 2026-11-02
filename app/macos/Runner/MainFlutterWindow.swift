import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  #if DEBUG
  // Available only to integration tests so synthetic events enter AppKit's queue.
  private var nativeDndTestChannel: FlutterMethodChannel?
  private var nativeDndTestEventNumber = 1
  #endif

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    #if DEBUG
    registerNativeDndTestChannel(for: flutterViewController)
    #endif

    super.awakeFromNib()
  }

  #if DEBUG
  private func registerNativeDndTestChannel(
    for flutterViewController: FlutterViewController
  ) {
    let channel = FlutterMethodChannel(
      name: "alula/native_dnd_test",
      binaryMessenger: flutterViewController
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(
          code: "native_input_unavailable",
          message: "The Alula window is no longer available",
          details: nil
        ))
        return
      }
      guard call.method == "scheduleDrag" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let sourceX = (arguments["sourceX"] as? NSNumber)?.doubleValue,
            let sourceY = (arguments["sourceY"] as? NSNumber)?.doubleValue,
            let targetX = (arguments["targetX"] as? NSNumber)?.doubleValue,
            let targetY = (arguments["targetY"] as? NSNumber)?.doubleValue
      else {
        result(FlutterError(
          code: "invalid_native_drag",
          message: "Expected sourceX/sourceY and targetX/targetY numbers",
          details: nil
        ))
        return
      }

      do {
        try self.scheduleNativeDrag(
          from: CGPoint(x: sourceX, y: sourceY),
          to: CGPoint(x: targetX, y: targetY)
        )
        result(nil)
      } catch {
        result(FlutterError(
          code: "native_input_unavailable",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
    nativeDndTestChannel = channel
  }

  private func scheduleNativeDrag(from source: CGPoint, to target: CGPoint) throws {
    guard let flutterView = (contentViewController as? FlutterViewController)?.view,
          let window = flutterView.window
    else {
      throw NSError(
        domain: "AlulaNativeDndTest",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Flutter view has no window"]
      )
    }

    _ = NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)

    func windowPoint(for flutterPoint: CGPoint) -> CGPoint {
      let nativeY = flutterView.isFlipped
        ? flutterPoint.y
        : flutterView.bounds.height - flutterPoint.y
      let localPoint = CGPoint(
        x: flutterPoint.x,
        y: nativeY
      )
      return flutterView.convert(localPoint, to: nil)
    }

    let sourcePoint = windowPoint(for: source)
    let targetPoint = windowPoint(for: target)
    var events: [(NSEvent.EventType, CGPoint)] = [
      (.mouseMoved, sourcePoint),
      (.leftMouseDown, sourcePoint),
    ]
    for step in 1...24 {
      let progress = CGFloat(step) / 24
      events.append((
        .leftMouseDragged,
        CGPoint(
          x: sourcePoint.x + (targetPoint.x - sourcePoint.x) * progress,
          y: sourcePoint.y + (targetPoint.y - sourcePoint.y) * progress
        )
      ))
    }
    events.append((.leftMouseUp, targetPoint))

    for (index, eventDescription) in events.enumerated() {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.04) {
        [weak self, weak window] in
        guard let self, let window, window.isVisible else { return }
        let eventType = eventDescription.0
        let isPressed = eventType == .leftMouseDown || eventType == .leftMouseDragged
        guard let event = NSEvent.mouseEvent(
          with: eventType,
          location: eventDescription.1,
          modifierFlags: [],
          timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber,
          context: nil,
          eventNumber: self.nativeDndTestEventNumber,
          clickCount: 1,
          pressure: isPressed ? 1 : 0
        ) else { return }
        self.nativeDndTestEventNumber += 1
        NSApp.postEvent(event, atStart: false)
      }
    }
  }
  #endif
}
