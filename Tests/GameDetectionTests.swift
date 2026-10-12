import Testing
@testable import PingCore

@Suite struct GameDetectionTests {
  @Test func gamesCategoryCounts() {
    #expect(GameDetection.isGame(bundleID: "com.example.shooter", category: "public.app-category.games"))
    #expect(GameDetection.isGame(bundleID: "com.example.rpg", category: "public.app-category.role-playing-games"))
  }

  @Test func riotAppsAlwaysCount() {
    #expect(GameDetection.isGame(bundleID: "com.riotgames.LeagueofLegends.GameClient", category: nil))
  }

  @Test func fullscreenBrowsersAndPlayersDoNot() {
    #expect(!GameDetection.isGame(bundleID: "company.thebrowser.dia", category: "public.app-category.productivity"))
    #expect(!GameDetection.isGame(bundleID: "com.apple.Safari", category: nil))
    #expect(!GameDetection.isGame(bundleID: nil, category: nil))
  }
}
