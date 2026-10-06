import Cocoa
import FlutterMacOS
import Sparkle

@main
class AppDelegate: FlutterAppDelegate {
  /// Sparkle, reading `SUFeedURL` and `SUPublicEDKey` from Info.plist. The
  /// feed is the latest GitHub release's `appcast.xml`; an update is only
  /// installed when its DMG carries an EdDSA signature from that key.
  let updater = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
    guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
    for item in appMenu.items where item.action == about {
      item.target = self
      item.action = #selector(showAbout(_:))
    }

    let check = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
      keyEquivalent: "")
    check.target = updater
    let afterAbout = (appMenu.items.firstIndex { $0.action == #selector(showAbout(_:)) } ?? -1) + 1
    appMenu.insertItem(check, at: afterAbout)
  }

  @objc func showAbout(_ sender: Any?) {
    (mainFlutterWindow as? MainFlutterWindow)?.appChannel?.invokeMethod("showAbout", arguments: nil)
  }
}
