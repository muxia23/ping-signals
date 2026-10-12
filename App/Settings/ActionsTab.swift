import AppKit
import PingCore
import SwiftUI

struct ActionsTab: View {
  @Bindable var model: SettingsModel
  @State private var showModern = false

  private static let main: [PingID] = [.danger, .omw, .assist, .missing, .generic]
  private static let modernOnly: [PingID] = [.push, .allin, .needvision, .enemyvision, .bait, .visioncleared]

  var body: some View {
    Form {
      Section {
        ForEach(Self.main, id: \.self) { ActionRow(id: $0, model: model) }
      } footer: {
        Text("Shortcuts and shell commands receive the ping and the front app, window and URL (PING_ID, FRONT_APP, FRONT_URL…).")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        DisclosureGroup("Modern wheel only", isExpanded: $showModern) {
          ForEach(Self.modernOnly, id: \.self) { ActionRow(id: $0, model: model) }
        }
      }
      HStack {
        Spacer()
        Button("Restore Defaults") { model.settings.actions = PingActions.defaults }
      }
    }
    .formStyle(.grouped)
  }
}

private struct ActionRow: View {
  let id: PingID
  @Bindable var model: SettingsModel

  private var config: Binding<ActionConfig> {
    Binding { model.settings.actions[id] ?? .none } set: { model.settings.actions[id] = $0 }
  }

  private var kind: Binding<ActionConfig.Kind> {
    Binding { config.wrappedValue.kind } set: { k in
      if k != config.wrappedValue.kind { config.wrappedValue = .blank(k) }
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(Names.ping(id)).frame(width: 100, alignment: .leading)
      Picker("", selection: kind) {
        ForEach(ActionConfig.Kind.allCases) { Text(Names.action($0)).tag($0) }
      }
      .labelsHidden().frame(width: 160)
      parameter.frame(maxWidth: .infinity, alignment: .leading)
      Button("Try") { model.tryAction(config.wrappedValue, id) }
        .disabled(!config.wrappedValue.isEffective)
    }
  }

  @ViewBuilder private var parameter: some View {
    switch config.wrappedValue {
    case .shortcut(let name):
      HStack(spacing: 4) {
        Picker("", selection: Binding { name } set: { config.wrappedValue = .shortcut($0) }) {
          Text("Choose…").tag("")
          ForEach(model.shortcuts.contains(name) || name.isEmpty ? model.shortcuts : [name] + model.shortcuts,
                  id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        Button { model.refreshShortcuts() } label: { Image(systemName: "arrow.clockwise") }
          .buttonStyle(.borderless).help("Reload shortcuts")
      }
    case .keystroke(let h):
      KeyRecorder(value: Binding { h } set: { config.wrappedValue = .keystroke($0) }, setRecording: model.setRecording)
    case .open(let s):
      HStack(spacing: 4) {
        TextField("https://… or app", text: Binding { s } set: { config.wrappedValue = .open($0) })
          .labelsHidden()
        Button("App…") { chooseApp() }
      }
    case .shell(let cmd):
      TextField("command", text: Binding { cmd } set: { config.wrappedValue = .shell($0) })
        .labelsHidden().font(.system(.body, design: .monospaced))
    default:
      EmptyView()
    }
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url { config.wrappedValue = .open(url.absoluteString) }
  }
}
