import PingCore

@MainActor
protocol PingAction: AnyObject {
  func perform(_ signal: PingSignal)
}

/// Signal handler that runs the action bound to each ping (see PingActions).
@MainActor
final class ActionRouter: SignalHandler {
  private let actions: [PingActionKind: PingAction]

  init(actions: [PingActionKind: PingAction]) { self.actions = actions }

  func handle(_ signal: PingSignal) {
    guard let kind = PingActions.shouldAct(on: signal) else { return }
    actions[kind]?.perform(signal)
  }
}
