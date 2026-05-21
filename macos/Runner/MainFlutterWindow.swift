import Cocoa
import FlutterMacOS
import LocalAuthentication
import macos_window_utils
import Security

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
      case "keychainRead":
        let args = call.arguments as? [String: Any]
        let key = args?["key"] as? String ?? ""
        let reason = args?["reason"] as? String
          ?? "Unlock the saved password for this connection"

        // Auth gate lives in our code, not on the keychain item. ACLs
        // (.biometryAny / .userPresence) require a developer-cert
        // entitlement that ad-hoc-signed builds don't carry — SecItemAdd
        // returns errSecMissingEntitlement (-34018) if you try. Plain
        // keychain storage + LAContext.evaluatePolicy gives the same
        // Touch ID UX without needing the entitlement.
        let context = LAContext()
        var policyError: NSError?
        let canBio = context.canEvaluatePolicy(
          .deviceOwnerAuthenticationWithBiometrics,
          error: &policyError
        )
        let policy: LAPolicy = canBio
          ? .deviceOwnerAuthenticationWithBiometrics
          : .deviceOwnerAuthentication
        NSLog("[dbv.keychain] auth begin key=\(key) canBio=\(canBio)")
        context.evaluatePolicy(policy, localizedReason: reason) { success, authError in
          NSLog("[dbv.keychain] auth done key=\(key) success=\(success) err=\(authError?.localizedDescription ?? "nil")")
          DispatchQueue.main.async {
            result(success ? KeychainStore.read(key: key) : nil)
          }
        }
      case "keychainWrite":
        let args = call.arguments as? [String: Any]
        let key = args?["key"] as? String ?? ""
        let value = args?["value"] as? String ?? ""
        result(KeychainStore.write(key: key, value: value))
      case "keychainDelete":
        let args = call.arguments as? [String: Any]
        let key = args?["key"] as? String ?? ""
        result(KeychainStore.delete(key: key))
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

/// Thin wrapper around SecItem* for storing per-key strings in the user's
/// default keychain. Items are scoped to this app's bundle identifier
/// automatically because sandboxed apps each get their own keychain
/// partition — no entitlement beyond app-sandbox is required for items
/// the app itself created.
///
/// Storage is intentionally plain: `kSecAttrAccessControl` (biometric /
/// user-presence ACLs) requires a developer-cert keychain entitlement
/// that ad-hoc-signed builds don't carry, so we keep items unprotected
/// at the keychain level and gate reads through `LAContext` in the
/// `keychainRead` method-channel handler instead.
enum KeychainStore {
  private static let service = "dbv.password"

  private static func baseQuery(_ key: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }

  static func read(key: String) -> String? {
    var query = baseQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    NSLog("[dbv.keychain] read store key=\(key) status=\(status)")
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func write(key: String, value: String) -> Bool {
    let data = value.data(using: .utf8) ?? Data()
    let query = baseQuery(key)
    let attrs: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    NSLog("[dbv.keychain] write key=\(key) updateStatus=\(updateStatus)")
    if updateStatus == errSecSuccess { return true }
    if updateStatus == errSecItemNotFound {
      var add = query
      add[kSecValueData as String] = data
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      NSLog("[dbv.keychain] write key=\(key) addStatus=\(addStatus)")
      return addStatus == errSecSuccess
    }
    return false
  }

  static func delete(key: String) -> Bool {
    let status = SecItemDelete(baseQuery(key) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
