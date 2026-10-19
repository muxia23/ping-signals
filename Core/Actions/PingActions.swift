import Foundation

/// What placing a ping does beyond its animation and sound. User-configurable per ping.
public enum ActionConfig: Equatable, Sendable, Codable {
  case none, retreat, todoPanel, chatGPT, codex, claudeQuickEntry
  /// Runs a Shortcuts.app shortcut by name.
  case shortcut(String)
  /// Presses a key combination; modifiers may be empty (e.g. F13).
  case keystroke(Hotkey)
  /// A web address, any `scheme://` link, or a file URL of an app.
  case open(String)
  /// One shell command line, run with `zsh -lc`.
  case shell(String)

  public enum Kind: String, CaseIterable, Sendable, Identifiable {
    case none, retreat, todoPanel, chatGPT, codex, claudeQuickEntry, shortcut, keystroke, open, shell
    public var id: String { rawValue }
  }

  public var kind: Kind {
    switch self {
    case .none: .none
    case .retreat: .retreat
    case .todoPanel: .todoPanel
    case .chatGPT: .chatGPT
    case .codex: .codex
    case .claudeQuickEntry: .claudeQuickEntry
    case .shortcut: .shortcut
    case .keystroke: .keystroke
    case .open: .open
    case .shell: .shell
    }
  }

  /// The action of `kind` with an empty parameter, used when the user switches kinds.
  public static func blank(_ kind: Kind) -> ActionConfig {
    switch kind {
    case .none: .none
    case .retreat: .retreat
    case .todoPanel: .todoPanel
    case .chatGPT: .chatGPT
    case .codex: .codex
    case .claudeQuickEntry: .claudeQuickEntry
    case .shortcut: .shortcut("")
    case .keystroke: .keystroke(Hotkey(mods: [], vk: 0))
    case .open: .open("")
    case .shell: .shell("")
    }
  }

  /// False for `.none` and for actions whose parameter is still blank.
  public var isEffective: Bool {
    func filled(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    switch self {
    case .none: return false
    case .retreat, .todoPanel, .chatGPT, .codex, .claudeQuickEntry: return true
    case .shortcut(let s), .open(let s), .shell(let s): return filled(s)
    case .keystroke(let h): return KeyMap.vkToKeyCode(h.vk) != nil
    }
  }

  private enum Keys: String, CodingKey { case type, value }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch Kind(rawValue: type) {
    case .none?: self = .none
    case .retreat?: self = .retreat
    case .todoPanel?: self = .todoPanel
    case .chatGPT?: self = .chatGPT
    case .codex?: self = .codex
    case .claudeQuickEntry?: self = .claudeQuickEntry
    case .shortcut?: self = .shortcut(try c.decode(String.self, forKey: .value))
    case .keystroke?: self = .keystroke(try c.decode(Hotkey.self, forKey: .value))
    case .open?: self = .open(try c.decode(String.self, forKey: .value))
    case .shell?: self = .shell(try c.decode(String.self, forKey: .value))
    case nil: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action \(type)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(kind.rawValue, forKey: .type)
    switch self {
    case .none, .retreat, .todoPanel, .chatGPT, .codex, .claudeQuickEntry: break
    case .shortcut(let s), .open(let s), .shell(let s): try c.encode(s, forKey: .value)
    case .keystroke(let h): try c.encode(h, forKey: .value)
    }
  }
}

public enum PingActions {
  /// Danger retreats, On My Way opens the todo panel, Assist Me calls ChatGPT.
  public static let defaults: [PingID: ActionConfig] = Dictionary(uniqueKeysWithValues: PingID.allCases.map { id in
    switch id {
    case .danger: (id, .retreat)
    case .omw: (id, .todoPanel)
    case .assist: (id, .chatGPT)
    default: (id, .none)
    }
  })

  /// The action to run for a placed ping, or nil (menu-bar previews never act).
  public static func shouldAct(on signal: PingSignal, actions: [PingID: ActionConfig]) -> ActionConfig? {
    guard signal.source != .preview, let c = actions[signal.ping], c.isEffective else { return nil }
    return c
  }

  /// Entry by entry: unknown pings and malformed entries are skipped; missing pings keep their default.
  public static func decodeLeniently(_ value: Any?) -> [PingID: ActionConfig] {
    var out = defaults
    guard let obj = value as? [String: Any] else { return out }
    for (key, v) in obj {
      guard let id = PingID(rawValue: key), JSONSerialization.isValidJSONObject([v]),
            let d = try? JSONSerialization.data(withJSONObject: [v]),
            let c = (try? JSONDecoder().decode([ActionConfig].self, from: d))?.first else { continue }
      out[id] = c
    }
    return out
  }
}
