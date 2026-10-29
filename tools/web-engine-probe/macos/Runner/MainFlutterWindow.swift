import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerWebArchiveLoader(for: flutterViewController)

    super.awakeFromNib()
  }

  private func registerWebArchiveLoader(for flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "alula.p00_4/webarchive",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self, weak flutterViewController] call, result in
      guard call.method == "loadWebArchive" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let archiveData = arguments["data"] as? FlutterStandardTypedData,
        let baseURLString = arguments["baseURL"] as? String,
        let baseURL = URL(string: baseURLString),
        let self,
        let rootView = flutterViewController?.view,
        let webView = self.findWebView(in: rootView)
      else {
        result(
          FlutterError(
            code: "webarchive-unavailable",
            message: "Could not find the probe WKWebView or archive data",
            details: nil
          )
        )
        return
      }

      guard
        webView.load(
          archiveData.data,
          mimeType: "application/x-webarchive",
          characterEncodingName: "UTF-8",
          baseURL: baseURL
        ) != nil
      else {
        result(
          FlutterError(
            code: "webarchive-load-failed",
            message: "WKWebView did not start loading the Web Archive",
            details: nil
          )
        )
        return
      }
      result(true)
    }
  }

  private func findWebView(in view: NSView) -> WKWebView? {
    if let webView = view as? WKWebView {
      return webView
    }
    for subview in view.subviews {
      if let webView = findWebView(in: subview) {
        return webView
      }
    }
    return nil
  }
}
