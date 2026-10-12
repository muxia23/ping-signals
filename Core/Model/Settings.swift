import Foundation

public enum LanguagePref: String, Codable, CaseIterable, Sendable { case auto, zhHans, en }

public struct Settings: Codable, Equatable, Sendable {
  public var version = 1
  public var enabledOnStart = true
  public var style: WheelStyle = .classic
  public var trigger: Trigger = .option
  public var dragThresholdPx = 8
  public var clickPing = false
  /// Modern only; classic always places the generic ping.
  public var clickPingID: PingID = .generic
  public var gameCheck = true
  /// Modern only.
  public var wheel: [PingID] = PingCatalog.defaultModernWheel
  public var toggleHotkey: Hotkey = .defaultToggle
  public var pingSizePx = 110
  public var pingDurationS = 3.2
  public var volume = 70
  public var muted = false
  public var tickSound = true
  public var launchAtLogin = false
  public var language: LanguagePref = .auto
  public var autoUpdateCheck = true

  public static let dragRange = 2...40
  public static let sizeRange = 60...220
  public static let durationRange = 1.0...8.0
  public static let volumeRange = 0...100

  public init() {}

  public func gestureConfig(enabled: Bool) -> GestureConfig {
    var c = GestureConfig()
    c.trigger = trigger
    c.clickPing = clickPing
    c.gameCheck = gameCheck
    c.dragThresholdPx = dragThresholdPx
    c.toggle = toggleHotkey
    c.enabled = enabled
    return c
  }

  /// Decodes field by field: a missing or invalid field takes its default, numbers are clamped,
  /// so an old or hand-edited file never loses the rest of the settings.
  public static func decodeLeniently(_ data: Data) -> Settings {
    var s = Settings()
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return s }
    func field<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
      guard let v = obj[key], let d = try? JSONSerialization.data(withJSONObject: [v]) else { return nil }
      return (try? JSONDecoder().decode([T].self, from: d))?.first
    }
    func clamp<T: Comparable>(_ v: T, _ r: ClosedRange<T>) -> T { min(max(v, r.lowerBound), r.upperBound) }

    if let v = field("enabledOnStart", Bool.self) { s.enabledOnStart = v }
    if let v = field("style", WheelStyle.self) { s.style = v }
    if let v = field("trigger", Trigger.self) { s.trigger = v }
    if let v = field("dragThresholdPx", Int.self) { s.dragThresholdPx = clamp(v, dragRange) }
    if let v = field("clickPing", Bool.self) { s.clickPing = v }
    if let v = field("clickPingID", PingID.self) { s.clickPingID = v }
    if let v = field("gameCheck", Bool.self) { s.gameCheck = v }
    if let v = field("wheel", [PingID].self), v.count == 8, Set(v).count == 8 { s.wheel = v }
    if let v = field("toggleHotkey", Hotkey.self), !v.mods.isDisjoint(with: [.control, .option, .command]) {
      s.toggleHotkey = v
    }
    if let v = field("pingSizePx", Int.self) { s.pingSizePx = clamp(v, sizeRange) }
    if let v = field("pingDurationS", Double.self) { s.pingDurationS = clamp(v, durationRange) }
    if let v = field("volume", Int.self) { s.volume = clamp(v, volumeRange) }
    if let v = field("muted", Bool.self) { s.muted = v }
    if let v = field("tickSound", Bool.self) { s.tickSound = v }
    if let v = field("launchAtLogin", Bool.self) { s.launchAtLogin = v }
    if let v = field("language", LanguagePref.self) { s.language = v }
    if let v = field("autoUpdateCheck", Bool.self) { s.autoUpdateCheck = v }
    // A custom trigger key can't be the pause shortcut's key.
    if case .key(let vk) = s.trigger, vk == s.toggleHotkey.vk { s.trigger = .option }
    return s
  }
}

public final class SettingsStore {
  private let defaults: UserDefaults
  private let key = "settings.v1"

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public func load() -> Settings {
    guard let data = defaults.data(forKey: key) else { return Settings() }
    return Settings.decodeLeniently(data)
  }

  public func save(_ s: Settings) {
    if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
  }
}
