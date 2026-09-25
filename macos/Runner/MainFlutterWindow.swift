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
    let channel = FlutterMethodChannel(name: "aperture/window", binaryMessenger: messenger)
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

    let keychain = FlutterMethodChannel(name: "aperture/keychain", binaryMessenger: messenger)
    keychain.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any],
            let account = args["account"] as? String else {
        result(FlutterError(code: "args", message: "account is required", details: nil))
        return
      }
      switch call.method {
      case "read":
        result(Keychain.read(account: account))
      case "write":
        guard let secret = args["secret"] as? String else {
          result(FlutterError(code: "args", message: "secret is required", details: nil))
          return
        }
        let status = Keychain.write(account: account, secret: secret)
        result(status == errSecSuccess
          ? nil
          : FlutterError(code: "keychain", message: Keychain.describe(status), details: nil))
      case "delete":
        Keychain.delete(account: account)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)

    super.awakeFromNib()
  }
}

/// Generic-password items in the login keychain, all under one service so
/// Keychain Access lists them together.
enum Keychain {
  static let service = "com.jwo1f.aperture"

  private static func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read(account: String) -> String? {
    var q = query(account: account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Replaces any existing item rather than updating it, so the new item
  /// carries this build's access list.
  static func write(account: String, secret: String) -> OSStatus {
    delete(account: account)
    var q = query(account: account)
    q[kSecValueData as String] = Data(secret.utf8)
    q[kSecAttrLabel as String] = "Aperture settings passphrase"
    return SecItemAdd(q as CFDictionary, nil)
  }

  static func delete(account: String) {
    SecItemDelete(query(account: account) as CFDictionary)
  }

  static func describe(_ status: OSStatus) -> String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
  }
}
