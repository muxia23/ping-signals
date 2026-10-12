import Foundation
import Testing
@testable import PingCore

@Suite struct PingActionsTests {
  @Test func mapping() {
    #expect(PingActions.kind(for: .assist) == .claudeQuickEntry)
    #expect(PingActions.kind(for: .omw) == .todoPanel)
    #expect(PingActions.kind(for: .danger) == .retreat)
    for id in PingID.allCases where ![.assist, .omw, .danger].contains(id) {
      #expect(PingActions.kind(for: id) == nil, "\(id)")
    }
  }

  @Test func previewsNeverAct() {
    func signal(_ source: PingSignal.Source) -> PingSignal {
      PingSignal(ping: .danger, style: .classic, point: GesturePoint(0, 0), frontApp: nil, time: Date(), source: source)
    }
    #expect(PingActions.shouldAct(on: signal(.wheel)) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.click)) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.preview)) == nil)
  }
}
