import Foundation
import PingCore

enum Names {
  static func ping(_ id: PingID) -> String {
    switch id {
    case .danger: String(localized: "Danger")
    case .push: String(localized: "Push")
    case .omw: String(localized: "On My Way")
    case .allin: String(localized: "All In")
    case .assist: String(localized: "Assist Me")
    case .needvision: String(localized: "Need Vision")
    case .missing: String(localized: "Enemy Missing")
    case .enemyvision: String(localized: "Enemy Vision")
    case .generic: String(localized: "Ping")
    case .bait: String(localized: "Bait")
    case .visioncleared: String(localized: "Vision Cleared")
    }
  }

  static func action(_ k: ActionConfig.Kind) -> String {
    switch k {
    case .none: String(localized: "Nothing")
    case .retreat: String(localized: "Retreat")
    case .todoPanel: String(localized: "Todo Panel")
    case .claudeQuickEntry: String(localized: "Call Claude")
    case .shortcut: String(localized: "Run Shortcut")
    case .keystroke: String(localized: "Press Keys")
    case .open: String(localized: "Open App or URL")
    case .shell: String(localized: "Run Shell Command")
    }
  }
}

