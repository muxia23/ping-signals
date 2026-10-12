import PingCore

@MainActor
protocol PingAction: AnyObject {
  func perform(_ signal: PingSignal)
}

/// Signal handler that runs the action bound to each ping.
@MainActor
final class ActionRouter: SignalHandler {
  private let runner: ActionRunner
  private let bindings: () -> [PingID: ActionConfig]

  init(runner: ActionRunner, bindings: @escaping () -> [PingID: ActionConfig]) {
    self.runner = runner
    self.bindings = bindings
  }

  func handle(_ signal: PingSignal) {
    guard let c = PingActions.shouldAct(on: signal, actions: bindings()) else { return }
    runner.run(c, signal: signal)
  }
}
