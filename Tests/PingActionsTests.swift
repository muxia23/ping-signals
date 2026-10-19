import Foundation
import Testing
@testable import PingCore

@Suite struct PingActionsTests {
  private func signal(_ id: PingID, _ source: PingSignal.Source = .wheel) -> PingSignal {
    PingSignal(ping: id, style: .classic, point: GesturePoint(0, 0), frontApp: nil, time: Date(), source: source)
  }

  @Test func defaultsCallChatGPT() {
    let d = PingActions.defaults
    #expect(d[.assist] == .chatGPT)
    #expect(d[.omw] == .todoPanel)
    #expect(d[.danger] == .retreat)
    #expect(d.count == PingID.allCases.count)
    for id in PingID.allCases where ![.assist, .omw, .danger].contains(id) { #expect(d[id] == ActionConfig.none, "\(id)") }
  }

  @Test func previewsNeverAct() {
    let a = PingActions.defaults
    #expect(PingActions.shouldAct(on: signal(.danger, .wheel), actions: a) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.danger, .click), actions: a) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.danger, .preview), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.assist, .wheel), actions: a) == .chatGPT)
    #expect(PingActions.shouldAct(on: signal(.assist, .preview), actions: a) == nil)
  }

  @Test func ineffectiveActionsDoNothing() {
    var a = PingActions.defaults
    a[.missing] = .shell("   ")
    a[.push] = .keystroke(Hotkey(mods: [], vk: 0))
    a[.bait] = .open("")
    #expect(PingActions.shouldAct(on: signal(.missing), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.push), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.bait), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.generic), actions: a) == nil)
    a[.missing] = .shell("say hi")
    #expect(PingActions.shouldAct(on: signal(.missing), actions: a) == .shell("say hi"))
  }

  @Test func codexBindingActsWithoutChangingChatGPTDefault() {
    var a = PingActions.defaults
    a[.missing] = .codex
    #expect(a[.assist] == .chatGPT)
    #expect(PingActions.shouldAct(on: signal(.missing), actions: a) == .codex)
    #expect(PingActions.shouldAct(on: signal(.missing, .preview), actions: a) == nil)
  }

  @Test func codableRoundTrip() throws {
    let all: [ActionConfig] = [.none, .retreat, .todoPanel, .chatGPT, .codex, .claudeQuickEntry, .shortcut("翻译"),
                               .keystroke(Hotkey(mods: [.command, .shift], vk: 0x41)), .open("https://x.y"), .shell("ls")]
    for c in all {
      let back = try JSONDecoder().decode(ActionConfig.self, from: JSONEncoder().encode(c))
      #expect(back == c)
    }
    let json = String(decoding: try JSONEncoder().encode(ActionConfig.shortcut("A")), as: UTF8.self)
    #expect(json.contains(#""type":"shortcut""#) && json.contains(#""value":"A""#))
  }

  @Test func blankPerKind() {
    for k in ActionConfig.Kind.allCases { #expect(ActionConfig.blank(k).kind == k) }
  }
}
