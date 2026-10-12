import AppKit
import ApplicationServices

/// Waits for Accessibility permission, then calls `onGranted` once. Plan 2 replaces the system prompt
/// with a guidance window.
@MainActor
final class AccessibilityGate {
  private var timer: Timer?

  var isTrusted: Bool { AXIsProcessTrusted() }

  func waitForPermission(onGranted: @escaping @MainActor () -> Void) {
    if isTrusted { onGranted(); return }
    // The literal value of kAXTrustedCheckOptionPrompt (the global var is not concurrency-safe in Swift 6).
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
      guard AXIsProcessTrusted() else { return }
      t.invalidate()
      MainActor.assumeIsolated {
        self?.timer = nil
        onGranted()
      }
    }
  }

  static func openSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
