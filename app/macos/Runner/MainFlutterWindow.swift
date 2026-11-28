import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let dragInput = FlutterMethodChannel(
      name: "alula/drag_input",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    dragInput.setMethodCallHandler { call, result in
      guard call.method == "splitTogglePressed" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(NSEvent.modifierFlags.contains(.shift))
    }
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }
}
