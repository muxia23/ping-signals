/// What placing a ping does beyond its animation and sound.
public enum PingActionKind: Equatable, Sendable {
  case claudeQuickEntry, todoPanel, retreat
}

public enum PingActions {
  /// The same in both styles. Pings without an entry only animate.
  public static func kind(for id: PingID) -> PingActionKind? {
    switch id {
    case .assist: return .claudeQuickEntry
    case .omw: return .todoPanel
    case .danger: return .retreat
    default: return nil
    }
  }

  public static func shouldAct(on signal: PingSignal) -> PingActionKind? {
    signal.source == .preview ? nil : kind(for: signal.ping)
  }
}
