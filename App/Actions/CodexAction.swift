import AppKit
import PingCore

/// Opens Codex without submitting a prompt or sharing front-app context.
@MainActor
final class CodexAction: PingAction {
  private static let website = URL(string: "https://chatgpt.com/codex")!
  private var opening = false

  func perform(_ signal: PingSignal) {
    guard !opening else { return }
    let workspace = NSWorkspace.shared
    guard let appURL = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
      workspace.open(Self.website)
      return
    }

    opening = true
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { [weak self] app, error in
      let failed = error != nil || app == nil
      Task { @MainActor in
        self?.opening = false
        if failed {
          NSLog("ping-signals: Codex could not be opened; opening the web app")
          NSWorkspace.shared.open(Self.website)
        }
      }
    }

    let bundle = Bundle(url: appURL)
    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
    if name == "ChatGPT" {
      // The unified desktop app retains Codex's bundle ID. Explicitly select Codex mode
      // and target this app even if another installation owns the URL scheme.
      workspace.open([URL(string: "codex://new?mode=codex")!], withApplicationAt: appURL,
                     configuration: configuration, completionHandler: completion)
    } else {
      // Standalone Codex: activate it without requiring support for the newer mode link.
      workspace.openApplication(at: appURL, configuration: configuration,
                                completionHandler: completion)
    }
  }
}
