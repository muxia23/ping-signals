import AppKit
import PingCore

@MainActor
final class OpenAIAction: PingAction {
  enum Mode: String, Sendable {
    case chat
    case codex
  }
  private let mode: Mode
  private var opening = false
  init(_ mode: Mode) {
    self.mode = mode
  }
  // Two modes correspond to their respective web versions.
  private var website: URL {
    URL(
      string: mode == .chat
        ? "https://chatgpt.com/"
        : "https://chatgpt.com/codex"
    )!
  }

  func perform(_ signal: PingSignal) {
    guard !opening else { return }

    let workspace = NSWorkspace.shared
    let fallback = website
    // When no applicable desktop app is found
    // open the corresponding web version.
    guard let target = desktopTarget(in: workspace) else {
      workspace.open(fallback)
      return
    }

    opening = true
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let completion: @Sendable (NSRunningApplication?, Error?) -> Void = {
      [weak self] app, error in

      let failed = error != nil || app == nil

      Task { @MainActor in
        self?.opening = false
        if failed {
          NSLog("ping-signals: assistant launch failed; opening the web app")
          NSWorkspace.shared.open(fallback)
        }
      }
    }

    if let link = target.link {
      workspace.open(
        [link],
        withApplicationAt: target.appURL,
        configuration: configuration,
        completionHandler: completion
      )
    } else {
      workspace.openApplication(
        at: target.appURL,
        configuration: configuration,
        completionHandler: completion
      )
    }
  }

  private func desktopTarget(
    in workspace: NSWorkspace
  ) -> (appURL: URL, link: URL?)? {

    if let appURL = workspace.urlForApplication(
      withBundleIdentifier: "com.openai.codex"
    ) {
      let bundle = Bundle(url: appURL)
      let name = bundle?.object(
        forInfoDictionaryKey: "CFBundleDisplayName"
      ) as? String
        ?? bundle?.object(
          forInfoDictionaryKey: "CFBundleName"
        ) as? String

      if name == "ChatGPT" {
        // Compatibility Notes
        // ChatGPT The desktop macOS management configuration domain still uses com.openai.codex:
        // https://help.openai.com/en/articles/20001535-manage-chatgpt-desktop-browser-policies-with-mdm
        // Official document confirms retention of codex: Protocol:
        // https://learn.chatgpt.com/docs/reference/commands#deep-links
        // But the document above does not list the mode=chat/codex parameter.
        // The basis for these parameters is the routing implementation within the ChatGPT 26.930.51102 application package.
        // This is a compatibility handling for dependency versions and does not constitute a stability commitment for the public API.
        return (
          appURL,
          URL(string: "codex://new?mode=\(mode.rawValue)")!
        )
      }
      if mode == .codex {
        return (appURL, nil)
      }
    }

    if mode == .chat,
       let appURL = workspace.urlForApplication(
         withBundleIdentifier: "com.openai.chat"
       ) {
      return (appURL, nil)
    }
    return nil
  }
}