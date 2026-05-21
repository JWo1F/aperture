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
      case "getWindowFrame":
        let frame = window.frame
        result([
          "x": frame.origin.x,
          "y": frame.origin.y,
          "w": frame.size.width,
          "h": frame.size.height,
        ])
      case "setWindowFrame":
        if let args = call.arguments as? [String: Any],
           let x = args["x"] as? Double,
           let y = args["y"] as? Double,
           let w = args["w"] as? Double,
           let h = args["h"] as? Double {
          let target = NSRect(x: x, y: y, width: w, height: h)
          // Constrain to a screen that actually contains the origin so
          // we don't paint off-screen if monitors changed.
          let onScreen = NSScreen.screens.contains { s in
            s.visibleFrame.contains(NSPoint(x: x, y: y))
          }
          if onScreen {
            window.setFrame(target, display: true)
          }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)

    super.awakeFromNib()
  }
}
