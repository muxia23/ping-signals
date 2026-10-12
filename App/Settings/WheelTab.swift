import PingCore
import SwiftUI

struct WheelTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    // A grouped form like the other tabs, so every tab has the same background.
    Form {
      HStack(spacing: 28) {
        styleCard(.classic, title: "Classic (2022)", subtitle: "4 pings")
        styleCard(.modern, title: "Modern", subtitle: "8 pings")
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    }
    .formStyle(.grouped)
  }

  /// A picture of each wheel, so the difference is obvious; clicking one selects it.
  private func styleCard(_ style: WheelStyle, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
    let selected = model.settings.style == style
    return Button { model.settings.style = style } label: {
      VStack(spacing: 4) {
        Image(decorative: WheelThumbnails.image(style), scale: 2)
          .resizable().interpolation(.high).frame(width: 200, height: 200)
        Text(title).font(.title3.bold())
        Text(subtitle).font(.callout).foregroundStyle(.secondary)
      }
      .padding(14)
      .frame(width: 250)
      .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.12) : .clear))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.3),
                                                               lineWidth: selected ? 2 : 1))
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
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
