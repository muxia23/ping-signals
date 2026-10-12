import PingCore
import SwiftUI

struct WheelTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(spacing: 16) {
      Picker("Style", selection: $model.settings.style) {
        Text("Classic (2022)").tag(WheelStyle.classic)
        Text("Modern").tag(WheelStyle.modern)
      }
      .pickerStyle(.segmented)
      .frame(width: 300)

      if model.settings.style == .classic { classic } else { modern }
      Spacer()
    }
    .padding(20)
  }

  /// Classic slots are fixed: up, right, down, left.
  private var classic: some View {
    VStack(spacing: 10) {
      Text("↑ " + Names.ping(.danger))
      HStack(spacing: 40) {
        Text("← " + Names.ping(.missing))
        Text("⌥ + click: \(Names.ping(.generic))").foregroundStyle(.secondary)
        Text(Names.ping(.omw) + " →")
      }
      Text("↓ " + Names.ping(.assist))
      Text("The classic wheel is fixed.").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
    }
    .font(.title3)
  }

  private var modern: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle().strokeBorder(.quaternary, lineWidth: 1).frame(width: 300, height: 300)
        ForEach(0..<8, id: \.self) { slot in
          let a = Double(slot) * .pi / 4
          slotPicker(slot).offset(x: sin(a) * 150, y: -cos(a) * 150)
        }
        Picker("", selection: $model.settings.clickPingID) {
          ForEach(PingID.allCases, id: \.self) { Text(Names.ping($0)).tag($0) }
        }
        .labelsHidden().frame(width: 130)
        .help("Placed by trigger key + click")
      }
      .frame(width: 440, height: 360)
      Text("Choosing a ping that's already on the wheel swaps the two slots. The centre is the trigger-key + click ping.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 440)
      Button("Restore Defaults") {
        model.settings.wheel = PingCatalog.defaultModernWheel
        model.settings.clickPingID = .generic
      }
    }
  }

  private func slotPicker(_ slot: Int) -> some View {
    Picker("", selection: Binding {
      model.settings.wheel[slot]
    } set: { id in
      model.settings.wheel = WheelEdit.assign(id, toSlot: slot, in: model.settings.wheel)
    }) {
      ForEach(PingID.allCases.filter { $0 != .generic }, id: \.self) { Text(Names.ping($0)).tag($0) }
    }
    .labelsHidden()
    .frame(width: 130)
  }
}
