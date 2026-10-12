import PingCore
import SwiftUI

struct TriggerTab: View {
  @Bindable var model: SettingsModel

  private enum Choice: Hashable { case option, control, shift, command, mouse4, mouse5, custom }

  private var choice: Binding<Choice> {
    Binding {
      switch model.settings.trigger {
      case .option: .option
      case .control: .control
      case .shift: .shift
      case .command: .command
      case .mouse4: .mouse4
      case .mouse5: .mouse5
      case .key: .custom
      }
    } set: { c in
      let t: Trigger = switch c {
      case .option: .option
      case .control: .control
      case .shift: .shift
      case .command: .command
      case .mouse4: .mouse4
      case .mouse5: .mouse5
      case .custom: .key(model.settings.toggleHotkey.vk == 0xC0 ? 0x7C : 0xC0)  // ` (or F13)
      }
      if t != model.settings.trigger { model.settings.trigger = t }
    }
  }

  private var customKey: Binding<Hotkey> {
    Binding {
      if case .key(let vk) = model.settings.trigger { return Hotkey(mods: [], vk: vk) }
      return Hotkey(mods: [], vk: 0)
    } set: { model.settings.trigger = .key($0.vk) }
  }

  var body: some View {
    Form {
      Picker("Trigger key", selection: choice) {
        Text("⌥ Option").tag(Choice.option)
        Text("⌃ Control").tag(Choice.control)
        Text("⇧ Shift").tag(Choice.shift)
        Text("⌘ Command").tag(Choice.command)
        Text("Mouse button 4").tag(Choice.mouse4)
        Text("Mouse button 5").tag(Choice.mouse5)
        Text("Custom key…").tag(Choice.custom)
      }
      if case .key = model.settings.trigger {
        LabeledContent("Custom key") {
          KeyRecorder(value: customKey, validate: { h in
            h.vk == model.settings.toggleHotkey.vk ? String(localized: "Used by the pause shortcut") : nil
          }, setRecording: model.setRecording)
        }
      }
      LabeledContent("Drag distance") {
        HStack {
          Slider(value: Binding { Double(model.settings.dragThresholdPx) } set: { model.settings.dragThresholdPx = Int($0) },
                 in: Double(Settings.dragRange.lowerBound)...Double(Settings.dragRange.upperBound), step: 1)
          Text("\(model.settings.dragThresholdPx) px").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
      }
      Toggle("Trigger key + click places a ping", isOn: $model.settings.clickPing)
      Toggle("Let clicks through in full-screen games", isOn: $model.settings.gameCheck)
    }
    .formStyle(.grouped)
  }
}

struct PingsSoundTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      LabeledContent("Ping size") {
        HStack {
          Slider(value: Binding { Double(model.settings.pingSizePx) } set: { model.settings.pingSizePx = Int($0) },
                 in: Double(Settings.sizeRange.lowerBound)...Double(Settings.sizeRange.upperBound), step: 5)
          Text("\(model.settings.pingSizePx) px").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      LabeledContent("Ping duration") {
        HStack {
          Slider(value: $model.settings.pingDurationS, in: Settings.durationRange, step: 0.1)
          Text(String(format: "%.1f s", model.settings.pingDurationS)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      LabeledContent("Volume") {
        HStack {
          Slider(value: Binding { Double(model.settings.volume) } set: { model.settings.volume = Int($0) }, in: 0...100, step: 1)
          Text("\(model.settings.volume)%").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      Toggle("Mute", isOn: $model.settings.muted)
      Toggle("Tick sound when moving over the wheel", isOn: $model.settings.tickSound)
    }
    .formStyle(.grouped)
  }
}

struct GeneralTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      LabeledContent("Pause shortcut") {
        KeyRecorder(value: $model.settings.toggleHotkey, validate: { h in
          if h.mods.isDisjoint(with: [.control, .option, .command]) { return String(localized: "Include ⌃, ⌥ or ⌘") }
          if case .key(let vk) = model.settings.trigger, vk == h.vk { return String(localized: "Used by the trigger key") }
          return nil
        }, setRecording: model.setRecording)
      }
      Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
      Picker("Language", selection: $model.settings.language) {
        Text("Automatic").tag(LanguagePref.auto)
        Text(verbatim: "简体中文").tag(LanguagePref.zhHans)
        Text(verbatim: "English").tag(LanguagePref.en)
      }
      if model.settings.language != model.launchLanguage {
        HStack {
          Text("Takes effect after a restart").foregroundStyle(.secondary)
          Spacer()
          Button("Restart Now") { model.restart() }
        }
      }
      LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
    }
    .formStyle(.grouped)
  }
}
