import Foundation
import Testing
@testable import PingCore

@Suite struct ActionContextTests {
  private let signal = PingSignal(ping: .missing, style: .modern, point: GesturePoint(-108, -540),
                                  frontApp: "com.apple.Safari", time: Date(), source: .wheel)

  @Test func environmentHasEveryKnownField() {
    let front = TodoContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs", url: "https://a.b")
    let env = ActionContext(signal: signal, front: front).environment
    #expect(env == ["PING_ID": "missing", "PING_STYLE": "modern", "PING_X": "-108", "PING_Y": "-540",
                    "FRONT_APP": "Safari", "FRONT_BUNDLE_ID": "com.apple.Safari", "WINDOW_TITLE": "Docs",
                    "FRONT_URL": "https://a.b"])
  }

  @Test func missingFieldsAreLeftOut() throws {
    let ctx = ActionContext(signal: signal, front: TodoContext(appName: "Finder"))
    #expect(ctx.environment["FRONT_URL"] == nil && ctx.environment["WINDOW_TITLE"] == nil)
    let obj = try JSONSerialization.jsonObject(with: ctx.jsonData()) as! [String: Any]
    #expect(obj["ping"] as? String == "missing")
    #expect(obj["x"] as? Int == -108)
    #expect(obj["app"] as? String == "Finder")
    #expect(obj["url"] == nil)
  }
}
