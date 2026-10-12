import Foundation
import Testing
@testable import PingCore

@Suite struct PingCatalogTests {
  @Test func classicWheelIsFixedCompass() {
    #expect(PingCatalog.wheel(style: .classic, modernWheel: PingCatalog.defaultModernWheel)
      == [.danger, .omw, .assist, .missing])
    #expect(WheelStyle.classic.slots == 4)
    #expect(PingCatalog.clickPing(style: .classic, modernClickPing: .bait) == .generic)
  }

  @Test func modernWheelFollowsSettings() {
    let custom: [PingID] = [.bait, .push, .omw, .allin, .assist, .needvision, .missing, .enemyvision]
    #expect(PingCatalog.wheel(style: .modern, modernWheel: custom) == custom)
    #expect(WheelStyle.modern.slots == 8)
    #expect(PingCatalog.clickPing(style: .modern, modernClickPing: .bait) == .bait)
  }

  @Test func everyWheelPingHasADefinition() {
    for style in WheelStyle.allCases {
      let ids = PingCatalog.wheel(style: style, modernWheel: PingCatalog.defaultModernWheel)
        + [PingCatalog.clickPing(style: style, modernClickPing: .generic)]
      for id in ids { #expect(PingCatalog.def(id, style: style) != nil, "\(style) \(id)") }
    }
    for id in PingID.allCases { #expect(PingCatalog.def(id, style: .modern) != nil) }
  }

  @Test func classicDefinitions() {
    let missing = PingCatalog.def(.missing, style: .classic)!
    #expect(missing.art == ["ping-mia_02"])
    #expect(missing.base == ["ping-mia-base", "ping-mia-base-outer"])
    #expect(missing.sound == "MIA")
    #expect(missing.color == 0xB2A323)
    #expect(missing.wheelIcon == .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)))
    #expect(PingCatalog.def(.danger, style: .classic)?.sound == "GetBack")
    #expect(PingCatalog.def(.push, style: .classic) == nil)
  }

  @Test func allSoundsListsEachOnce() {
    let s = PingCatalog.allSounds
    #expect(Set(s).count == s.count)
    #expect(s.count == 13)
    #expect(s.contains("GetBack") && s.contains("button") && s.contains("SRP_12"))
  }
}
