import Testing
@testable import PingCore

@Suite struct RetreatStateTests {
  private func app(_ pid: Int32, regular: Bool = true, hidden: Bool = false, me: Bool = false) -> RunningApp {
    RunningApp(pid: pid, isRegular: regular, isHidden: hidden, isSelf: me)
  }

  @Test func retreatHidesVisibleRegularAppsButNotSelf() {
    var s = RetreatState()
    let plan = s.toggle(running: [app(1), app(2, hidden: true), app(3, regular: false), app(4, me: true), app(5)], frontmost: 5)
    #expect(plan == RetreatPlan(hide: [1, 5]))
    #expect(s.isRetreated)
  }

  @Test func restoreUnhidesAndActivatesFormerFront() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(5)], frontmost: 5)
    let plan = s.toggle(running: [app(1, hidden: true), app(5, hidden: true)], frontmost: nil)
    #expect(plan == RetreatPlan(unhide: [1, 5], activate: 5))
    #expect(!s.isRetreated)
  }

  @Test func restoreSkipsAppsThatQuit() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(2)], frontmost: 2)
    let plan = s.toggle(running: [app(1, hidden: true)], frontmost: nil)
    #expect(plan == RetreatPlan(unhide: [1], activate: nil))
  }

  @Test func frontmostNotHiddenIsNotReactivated() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(4, me: true)], frontmost: 4)   // our own app was in front
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan(unhide: [1], activate: nil))
  }

  @Test func cyclesRepeatedly() {
    var s = RetreatState()
    for _ in 0..<3 {
      #expect(s.toggle(running: [app(1)], frontmost: 1) == RetreatPlan(hide: [1]))
      #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan(unhide: [1], activate: 1))
    }
  }

  @Test func retreatWithNothingVisibleStillToggles() {
    var s = RetreatState()
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan())
    #expect(s.isRetreated)
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan())
    #expect(!s.isRetreated)
  }
}
