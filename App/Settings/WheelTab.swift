import PingCore
import SwiftUI

struct WheelTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(spacing: 16) {
      HStack(spacing: 24) {
        styleCard(.classic, title: "Classic (2022)", subtitle: "4 fixed pings")
        styleCard(.modern, title: "Modern", subtitle: "8 pings, editable")
      }

      if model.settings.style == .classic { classic } else { modern }
      Spacer()
    }
    .padding(20)
  }

  /// A picture of each wheel, so the difference is obvious; clicking one selects it.
  private func styleCard(_ style: WheelStyle, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
    let selected = model.settings.style == style
    return Button { model.settings.style = style } label: {
      VStack(spacing: 4) {
        Image(decorative: WheelThumbnails.image(style), scale: 2)
          .resizable().interpolation(.high).frame(width: 120, height: 120)
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      .padding(10)
      .frame(width: 180)
      .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.12) : .clear))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.3),
                                                               lineWidth: selected ? 2 : 1))
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
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
        Circle().strokeBorder(.quaternary, lineWidth: 1).frame(width: 250, height: 250)
        ForEach(0..<8, id: \.self) { slot in
          let a = Double(slot) * .pi / 4
          slotPicker(slot).offset(x: sin(a) * 125, y: -cos(a) * 125)
        }
        Picker("", selection: $model.settings.clickPingID) {
          ForEach(PingID.allCases, id: \.self) { Text(Names.ping($0)).tag($0) }
        }
        .labelsHidden().frame(width: 130)
        .help("Placed by trigger key + click")
      }
      .frame(width: 440, height: 300)
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

/// Wheel pictures for the style cards, rendered once.
@MainActor
private enum WheelThumbnails {
  static let classic = ClassicWheelRenderer.render(wheel: PingCatalog.classicWheel, pixelScale: 2).idleImage()
  static let modern = ModernWheelRenderer.render(wheel: PingCatalog.defaultModernWheel, pixelScale: 2)
    .idleImage(fraction: 0.74)

  static func image(_ style: WheelStyle) -> CGImage { style == .classic ? classic : modern }
}
