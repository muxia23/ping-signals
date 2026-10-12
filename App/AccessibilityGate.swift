import AppKit
import ApplicationServices

/// Waits for Accessibility permission, then calls `onGranted` once. Plan 2 replaces the system prompt
/// with a guidance window. Calling it again replaces the previous wait.
@MainActor
final class AccessibilityGate {
  private var timer: Timer?

  var isTrusted: Bool { AXIsProcessTrusted() }

  /// `prompt`: also show the system's permission prompt (skipped when permission was revoked later:
  /// the menu's "Grant Accessibility…" item covers that).
  func waitForPermission(prompt: Bool = true, onGranted: @escaping @MainActor () -> Void) {
    timer?.invalidate()
    timer = nil
    if isTrusted { onGranted(); return }
    if prompt {
      // The literal value of kAXTrustedCheckOptionPrompt (the global var is not concurrency-safe in Swift 6).
      let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(opts)
    }
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] t in
      guard AXIsProcessTrusted() else { return }
      t.invalidate()
      MainActor.assumeIsolated {
        self?.timer = nil
        onGranted()
      }
    }
    RunLoop.main.add(timer, forMode: .common)  // keeps polling while a menu is open
    self.timer = timer
  }

  static func openSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
