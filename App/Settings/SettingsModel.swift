import AppKit
import Observation
import PingCore

/// The settings window's state. Edits go straight to the coordinator.
@MainActor @Observable
final class SettingsModel {
  var settings: Settings {
    didSet { if settings != oldValue { apply(settings) } }
  }
  var shortcuts: [String] = []
  /// Language the app is running in, to tell whether a restart is pending.
  let launchLanguage: LanguagePref

  @ObservationIgnored private let apply: (Settings) -> Void
  @ObservationIgnored let tryAction: (ActionConfig, PingID) -> Void
  @ObservationIgnored let setRecording: (Bool) -> Void

  init(settings: Settings, apply: @escaping (Settings) -> Void,
       tryAction: @escaping (ActionConfig, PingID) -> Void, setRecording: @escaping (Bool) -> Void) {
    self.settings = settings
    self.launchLanguage = settings.language
    self.apply = apply
    self.tryAction = tryAction
    self.setRecording = setRecording
  }

  func refreshShortcuts() {
    Task { shortcuts = await ActionRunner.listShortcuts() }
  }

  func restart() {
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}
