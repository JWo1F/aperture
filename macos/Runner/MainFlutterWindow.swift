import Cocoa
import FlutterMacOS
import macos_window_utils

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    let messenger = macOSWindowUtilsViewController.flutterViewController.engine.binaryMessenger
    let channel = FlutterMethodChannel(name: "dbv/window", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self else { result(nil); return }
      switch call.method {
      case "startDrag":
        if let event = NSApp.currentEvent {
          window.performDrag(with: event)
        }
        result(nil)
      case "toggleZoom":
        window.zoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)

    super.awakeFromNib()
  }
}
