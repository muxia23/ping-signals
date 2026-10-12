import Foundation
import Testing
@testable import PingCore

@Suite struct SettingsTests {
  private func decode(_ json: String) -> Settings {
    Settings.decodeLeniently(Data(json.utf8))
  }

  @Test func defaults() {
    let s = Settings()
    #expect(s.style == .classic)
    #expect(s.trigger == .option)
    #expect(s.dragThresholdPx == 8)
    #expect(s.wheel == PingCatalog.defaultModernWheel)
    #expect(s.toggleHotkey == .defaultToggle)
    #expect(s.pingSizePx == 110 && s.pingDurationS == 3.2 && s.volume == 70)
    #expect(s.gameCheck && s.tickSound && s.enabledOnStart && !s.clickPing && !s.muted)
  }

  @Test func roundTrip() throws {
    var s = Settings()
    s.style = .modern
    s.trigger = .key(0x56)
    s.volume = 40
    let back = Settings.decodeLeniently(try JSONEncoder().encode(s))
    #expect(back == s)
  }

  @Test func missingFieldsFallBack() {
    let s = decode(#"{"volume": 30}"#)
    #expect(s.volume == 30)
    #expect(s.style == .classic)
    #expect(s.pingSizePx == 110)
  }

  @Test func badFieldsFallBackIndividually() {
    let s = decode(#"{"volume": "loud", "style": "retro", "trigger": "hyper", "pingSizePx": 150}"#)
    #expect(s.volume == 70)
    #expect(s.style == .classic)
    #expect(s.trigger == .option)
    #expect(s.pingSizePx == 150)
  }

  @Test func outOfRangeIsClamped() {
    let s = decode(#"{"volume": 900, "dragThresholdPx": 0, "pingSizePx": 1000, "pingDurationS": 0.1}"#)
    #expect(s.volume == 100)
    #expect(s.dragThresholdPx == 2)
    #expect(s.pingSizePx == 220)
    #expect(s.pingDurationS == 1)
  }

  @Test func invalidWheelFallsBack() {
    #expect(decode(#"{"wheel": ["push"]}"#).wheel == PingCatalog.defaultModernWheel)
    #expect(decode(#"{"wheel": ["push","push","omw","allin","assist","needvision","missing","enemyvision"]}"#).wheel
      == PingCatalog.defaultModernWheel)
    let ok = #"{"wheel": ["bait","push","omw","allin","assist","needvision","missing","enemyvision"]}"#
    #expect(decode(ok).wheel.first == .bait)
  }

  @Test func hotkeyNeedsAPrimaryModifier() {
    #expect(decode(#"{"toggleHotkey": {"mods": 4, "vk": 80}}"#).toggleHotkey == .defaultToggle)  // Shift only
    #expect(decode(#"{"toggleHotkey": {"mods": 8, "vk": 80}}"#).toggleHotkey == Hotkey(mods: .command, vk: 80))
  }

  @Test func customTriggerCannotBeTheHotkeyKey() {
    let s = decode(#"{"trigger": "key:80"}"#)  // P, the default ⌃⌥P key
    #expect(s.trigger == .option)
  }

  @Test func gestureConfigMirrorsSettings() {
    var s = Settings()
    s.clickPing = true
    s.trigger = .mouse4
    let c = s.gestureConfig(enabled: false)
    #expect(c.clickPing && c.trigger == .mouse4 && c.gameCheck && !c.enabled && c.dragThresholdPx == 8)
  }

  @Test func storePersists() {
    let defaults = UserDefaults(suiteName: "ping-signals-tests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    #expect(store.load() == Settings())
    var s = Settings()
    s.style = .modern
    store.save(s)
    #expect(SettingsStore(defaults: defaults).load().style == .modern)
  }
}
