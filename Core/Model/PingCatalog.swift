public enum PingID: String, Codable, CaseIterable, Sendable {
  case danger, push, omw, allin, assist, needvision, missing, enemyvision, generic, bait, visioncleared
}

public enum WheelStyle: String, Codable, CaseIterable, Sendable {
  /// League before patch 12.22 (2022): four fixed pings.
  case classic
  /// League's current eight-slice wheel, editable.
  case modern

  public var slots: Int { self == .classic ? 4 : 8 }
}

/// A sprite in the classic wheel atlas (contextwheel_atlas.png), in atlas pixels, origin top-left.
public struct AtlasRect: Equatable, Sendable {
  public let x: Int, y: Int, w: Int, h: Int
  public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public enum WheelIcon: Equatable, Sendable {
  case texture(String)
  case atlas(AtlasRect)
}

public struct PingDef: Equatable, Sendable {
  public let id: PingID
  public let wheelIcon: WheelIcon
  /// Textures drawn at the ping location (file names without .png). Two entries = All In's clashing halves.
  public let art: [String]
  /// Classic only: white base textures tinted with `color`, drawn flat under the icon.
  public let base: [String]
  /// Sound file name without extension.
  public let sound: String
  /// 0xRRGGBB
  public let color: UInt32
}

public enum PingCatalog {
  public static let defaultModernWheel: [PingID] = [.danger, .push, .omw, .allin, .assist, .needvision, .missing, .enemyvision]
  public static let classicWheel: [PingID] = [.danger, .omw, .assist, .missing]
  public static let tickSound = "button"

  private static func modern(_ id: PingID, _ icon: String, _ art: [String], _ sound: String, _ color: UInt32) -> PingDef {
    PingDef(id: id, wheelIcon: .texture(icon), art: art, base: [], sound: sound, color: color)
  }

  /// From lolPing src/shared/pings.ts.
  private static let modernDefs: [PingID: PingDef] = Dictionary(uniqueKeysWithValues: [
    modern(.danger, "pingwheel_retreatrender", ["pingwheel_retreatrender"], "SRP_12", 0xFF3B55),
    modern(.push, "push", ["pingwheel_pushrender"], "SRP_9", 0x35D27A),
    modern(.omw, "omw", ["omw"], "OnMyWay", 0x2E8BFF),
    modern(.allin, "all_in", ["pingwheel_allin_render_01", "pingwheel_allin_render_02"], "SRP_4", 0xF2B320),
    modern(.assist, "assist_me", ["assist_me"], "ComeHere", 0x56D43C),
    modern(.needvision, "need_vision", ["need_vision"], "SRP_7", 0x56D43C),
    modern(.missing, "enemy_missing", ["enemy_missing"], "MIA", 0xF2C518),
    modern(.enemyvision, "enemy_vision", ["pingwheel_enemyvisionrender"], "AreaIsWarded", 0xFF3B55),
    modern(.generic, "generic_ping", ["pingwheel_basicpingrender"], "Base", 0x2E8BFF),
    modern(.bait, "pingwheel_baitrender", ["pingwheel_baitrender"], "SRP_11", 0xEFBC12),
    modern(.visioncleared, "vision_cleared", ["pingwheel_visionclearedrender"], "SRP_6", 0x2B80FF),
  ].map { ($0.id, $0) })

  /// Patch 12.21 assets (CommunityDragon). Colours are the peaks of each *-base-color.png ramp.
  private static let classicDefs: [PingID: PingDef] = Dictionary(uniqueKeysWithValues: [
    PingDef(id: .danger, wheelIcon: .atlas(AtlasRect(x: 467, y: 70, w: 26, h: 52)),
            art: ["ping-danger"], base: ["ping-danger-base"], sound: "GetBack", color: 0xFF0000),
    PingDef(id: .omw, wheelIcon: .atlas(AtlasRect(x: 389, y: 70, w: 54, h: 52)),
            art: ["ping-omw_02"], base: ["ping-omw-base"], sound: "OnMyWay", color: 0x26AA99),
    PingDef(id: .assist, wheelIcon: .atlas(AtlasRect(x: 464, y: 6, w: 46, h: 52)),
            art: ["ping-comehere_02"], base: ["ping-comehere-base"], sound: "ComeHere", color: 0x189CDB),
    PingDef(id: .missing, wheelIcon: .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)),
            art: ["ping-mia_02"], base: ["ping-mia-base", "ping-mia-base-outer"], sound: "MIA", color: 0xB2A323),
    PingDef(id: .generic, wheelIcon: .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)),
            art: ["sr_pings_blue_02"], base: ["ping-command-base"], sound: "Base", color: 0x3179C6),
  ].map { ($0.id, $0) })

  public static func def(_ id: PingID, style: WheelStyle) -> PingDef? {
    style == .classic ? classicDefs[id] : modernDefs[id]
  }

  public static func wheel(style: WheelStyle, modernWheel: [PingID]) -> [PingID] {
    style == .classic ? classicWheel : modernWheel
  }

  public static func clickPing(style: WheelStyle, modernClickPing: PingID) -> PingID {
    style == .classic ? .generic : modernClickPing
  }

  /// Every sound either style plays, each once.
  public static var allSounds: [String] {
    var seen = Set<String>(), out: [String] = []
    for d in Array(modernDefs.values) + Array(classicDefs.values) where seen.insert(d.sound).inserted { out.append(d.sound) }
    if seen.insert(tickSound).inserted { out.append(tickSound) }
    return out
  }

  /// Every texture either style draws (file names without .png), including the classic atlas.
  public static var allTextures: [String] {
    var seen = Set<String>(["contextwheel_atlas"]), out = ["contextwheel_atlas"]
    for d in Array(modernDefs.values) + Array(classicDefs.values) {
      var names = d.art + d.base
      if case .texture(let t) = d.wheelIcon { names.append(t) }
      for n in names where seen.insert(n).inserted { out.append(n) }
    }
    return out
  }
}
