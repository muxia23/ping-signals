import AppKit
import PingCore

/// Assist Me: opens Claude desktop's Quick Entry by double-tapping ⌥ (launching Claude first if needed).
@MainActor
final class ClaudeQuickEntryAction: PingAction {
  static let bundleID = "com.anthropic.claudefordesktop"
  /// Time for a freshly launched Claude to register its shortcut.
  private static let launchWait: Duration = .seconds(3)

  func perform(_ signal: PingSignal) {
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    if !running {
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
        NSLog("ping-signals: Claude.app not found")
        return
      }
      let cfg = NSWorkspace.OpenConfiguration()
      cfg.activates = false
      NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }
    SyntheticInput.whenModifiersReleased {
      if !running { try? await Task.sleep(for: Self.launchWait) }
      await SyntheticInput.doubleTapOption()
    }
  }
}
