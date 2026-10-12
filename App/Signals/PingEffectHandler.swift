import CoreGraphics
import PingCore

/// v1's only signal handler: draws the ping and plays its sound.
@MainActor
final class PingEffectHandler: SignalHandler {
  private let overlay: OverlayController
  private let sound: SoundPlayer
  private let settings: () -> Settings

  init(overlay: OverlayController, sound: SoundPlayer, settings: @escaping () -> Settings) {
    self.overlay = overlay
    self.sound = sound
    self.settings = settings
  }

  func handle(_ signal: PingSignal) {
    let s = settings()
    guard let def = PingCatalog.def(signal.ping, style: signal.style) else { return }
    overlay.spawnPing(def, style: signal.style, at: signal.point, size: CGFloat(s.pingSizePx), duration: s.pingDurationS)
    if !s.muted { sound.play(def.sound, volume: Float(s.volume) / 100) }
  }
}
