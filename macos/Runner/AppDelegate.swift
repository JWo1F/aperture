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
  ///
  /// No `super` call: FlutterAppDelegate doesn't implement this method, so
  /// forwarding raises an unrecognized-selector exception that AppKit
  /// swallows at launch — silently skipping everything after it.
  override func applicationDidFinishLaunching(_ notification: Notification) {
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
