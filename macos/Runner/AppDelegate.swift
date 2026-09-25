import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// The app menu's "About Aperture" opens AppKit's stock panel; point it
  /// at the Flutter About dialog instead.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    let about = #selector(NSApplication.orderFrontStandardAboutPanel(_:))
    for item in NSApp.mainMenu?.items.first?.submenu?.items ?? [] where item.action == about {
      item.target = self
      item.action = #selector(showAbout(_:))
    }
  }

  @objc func showAbout(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.appChannel?.invokeMethod("showAbout", arguments: nil)
  }
}
