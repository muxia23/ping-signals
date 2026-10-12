import Testing
@testable import PingCore

@Suite struct RetreatStateTests {
  private func app(_ pid: Int32, regular: Bool = true, hidden: Bool = false, me: Bool = false) -> RunningApp {
    RunningApp(pid: pid, isRegular: regular, isHidden: hidden, isSelf: me)
  }

  /// The front app is never hidden: hiding it makes macOS promote (and so unhide) another app.
  /// The wallpaper curtain covers it instead.
  @Test func retreatHidesVisibleRegularAppsExceptSelfAndFront() {
    var s = RetreatState()
    let plan = s.toggle(running: [app(1), app(2, hidden: true), app(3, regular: false), app(4, me: true), app(5)], frontmost: 5)
    #expect(plan == RetreatPlan(hide: [1]))
    #expect(s.isRetreated)
  }

  @Test func restoreUnhidesWhatWasHidden() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(2), app(5)], frontmost: 5)
    let plan = s.toggle(running: [app(1, hidden: true), app(2, hidden: true), app(5)], frontmost: 5)
    #expect(plan == RetreatPlan(unhide: [1, 2]))
    #expect(!s.isRetreated)
  }

  @Test func restoreSkipsAppsThatQuit() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(2), app(9)], frontmost: 9)
    #expect(s.toggle(running: [app(1, hidden: true), app(9)], frontmost: 9) == RetreatPlan(unhide: [1]))
  }

  @Test func cyclesRepeatedly() {
    var s = RetreatState()
    for _ in 0..<3 {
      #expect(s.toggle(running: [app(1), app(2)], frontmost: 2) == RetreatPlan(hide: [1]))
      #expect(s.toggle(running: [app(1, hidden: true), app(2)], frontmost: 2) == RetreatPlan(unhide: [1]))
    }
  }

  @Test func retreatWithNothingToHideStillToggles() {
    var s = RetreatState()
    #expect(s.toggle(running: [app(1)], frontmost: 1) == RetreatPlan())
    #expect(s.isRetreated)
    #expect(s.toggle(running: [app(1)], frontmost: 1) == RetreatPlan())
    #expect(!s.isRetreated)
  }
}
