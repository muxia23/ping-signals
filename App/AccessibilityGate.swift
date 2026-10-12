import AppKit
import ApplicationServices

/// Waits for Accessibility permission (polling once a second), then calls `onGranted` once. The guidance
/// is the onboarding window. Calling it again replaces the previous wait.
@MainActor
final class AccessibilityGate {
  private var timer: Timer?

  var isTrusted: Bool { AXIsProcessTrusted() }

  func waitForPermission(onGranted: @escaping @MainActor () -> Void) {
    timer?.invalidate()
    timer = nil
    if isTrusted { onGranted(); return }
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

  /// Puts the app into the Accessibility list (the system prompt) and opens the pane.
  static func requestAndOpenSettings() {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // literal kAXTrustedCheckOptionPrompt
    _ = AXIsProcessTrustedWithOptions(opts)
    openSettings()
  }

  static func openSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
