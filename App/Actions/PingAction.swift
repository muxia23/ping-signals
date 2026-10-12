import PingCore

@MainActor
protocol PingAction: AnyObject {
  func perform(_ signal: PingSignal)
}

/// Signal handler that runs the action bound to each ping.
@MainActor
final class ActionRouter: SignalHandler {
  private let actions: [ActionConfig.Kind: PingAction]
  private let bindings: () -> [PingID: ActionConfig]

  init(actions: [ActionConfig.Kind: PingAction], bindings: @escaping () -> [PingID: ActionConfig]) {
    self.actions = actions
    self.bindings = bindings
  }

  func handle(_ signal: PingSignal) {
    guard let c = PingActions.shouldAct(on: signal, actions: bindings()) else { return }
    actions[c.kind]?.perform(signal)
  }
}
