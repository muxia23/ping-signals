import CoreGraphics
import Testing
@testable import PingCore

@Suite struct CurtainPlanTests {
  // Global coordinates: built-in 1512×982 at the origin, external 1920×1080 above it.
  let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
  let external = CGRect(x: -108, y: -1080, width: 1920, height: 1080)

  @Test func coversScreensWithAFullscreenWindow() {
    let windows = [OnScreenWindow(pid: 10, bounds: external),                                    // fullscreen Dia
                   OnScreenWindow(pid: 11, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))]  // normal window
    #expect(CurtainPlan.screensToCover(screens: [builtIn, external], windows: windows, selfPID: 99) == [1])
  }

  @Test func ignoresOwnWindowsAndPartialWindows() {
    let windows = [OnScreenWindow(pid: 99, bounds: builtIn),                                      // our overlay
                   OnScreenWindow(pid: 12, bounds: CGRect(x: -108, y: -1080, width: 1000, height: 1080))]
    #expect(CurtainPlan.screensToCover(screens: [builtIn, external], windows: windows, selfPID: 99).isEmpty)
  }

  @Test func toleratesSubPointRounding() {
    let windows = [OnScreenWindow(pid: 10, bounds: CGRect(x: -108.4, y: -1080.3, width: 1920.5, height: 1080))]
    #expect(CurtainPlan.screensToCover(screens: [builtIn, external], windows: windows, selfPID: 99) == [1])
  }
}
