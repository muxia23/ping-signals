import AppKit
import PingCore

/// Opens ChatGPT, with a web fallback when the desktop app is unavailable.
/// No prompt, clipboard content or front-app context is sent to ChatGPT.
@MainActor
final class ChatGPTAction: PingAction {
  private static let website = URL(string: "https://chatgpt.com/")!
  private var opening = false

  func perform(_ signal: PingSignal) {
    guard !opening else { return }
    let workspace = NSWorkspace.shared
    guard let target = Self.desktopTarget(in: workspace) else {
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
          NSLog("ping-signals: ChatGPT could not be opened; opening the web app")
          NSWorkspace.shared.open(Self.website)
        }
      }
    }

    if let url = target.newChatURL {
      // Target the verified ChatGPT app explicitly, even if another app owns the URL scheme.
      workspace.open([url], withApplicationAt: target.appURL, configuration: configuration,
                     completionHandler: completion)
    } else {
      workspace.openApplication(at: target.appURL, configuration: configuration,
                                completionHandler: completion)
    }
  }

  private static func desktopTarget(in workspace: NSWorkspace) -> (appURL: URL, newChatURL: URL?)? {
    // The current ChatGPT desktop app retains this bundle ID and URL scheme. Require its
    // ChatGPT name as well so an older standalone Codex installation is never opened here.
    if let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.codex"),
       let bundle = Bundle(url: url),
       (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
         ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) == "ChatGPT" {
      return (url, URL(string: "codex://new?mode=chat")!)
    }
    // ChatGPT Classic: activate the app without assuming the user's global shortcut.
    if let url = workspace.urlForApplication(withBundleIdentifier: "com.openai.chat") {
      return (url, nil)
    }
    return nil
  }
}
