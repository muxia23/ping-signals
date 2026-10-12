import Foundation
import Testing
@testable import PingCore

@MainActor
private final class Recorder: SignalHandler {
  let name: String
  var log: [String]
  init(_ name: String, log: [String] = []) { self.name = name; self.log = log }
  func handle(_ signal: PingSignal) { log.append("\(name):\(signal.ping.rawValue)") }
}

@MainActor
@Suite struct SignalBusTests {
  private func signal(_ id: PingID) -> PingSignal {
    PingSignal(ping: id, style: .classic, point: GesturePoint(10, 20), frontApp: "com.apple.Safari",
               time: Date(timeIntervalSince1970: 0), source: .wheel)
  }

  @Test func deliversToHandlersInOrder() {
    let bus = SignalBus()
    let shared = Recorder("shared")
    let a = Recorder("a"), b = Recorder("b")
    bus.register(a)
    bus.register(b)
    bus.register(shared)
    bus.emit(signal(.missing))
    bus.emit(signal(.danger))
    #expect(a.log == ["a:missing", "a:danger"])
    #expect(b.log == ["b:missing", "b:danger"])
    #expect(bus.handlerCount == 3)
  }

  @Test func emptyBusIsFine() {
    SignalBus().emit(signal(.omw))
  }
}
