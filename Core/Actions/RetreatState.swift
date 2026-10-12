public struct RunningApp: Equatable, Sendable {
  public let pid: Int32
  /// Has a Dock icon and normal windows (NSApplication.ActivationPolicy.regular).
  public let isRegular: Bool
  public let isHidden: Bool
  public let isSelf: Bool
  public init(pid: Int32, isRegular: Bool, isHidden: Bool, isSelf: Bool) {
    self.pid = pid; self.isRegular = isRegular; self.isHidden = isHidden; self.isSelf = isSelf
  }
}

public struct RetreatPlan: Equatable, Sendable {
  public var hide: [Int32]
  public var unhide: [Int32]
  public var activate: Int32?
  public init(hide: [Int32] = [], unhide: [Int32] = [], activate: Int32? = nil) {
    self.hide = hide; self.unhide = unhide; self.activate = activate
  }
}

/// The Danger ping: the first press hides every visible app, the next one brings back exactly those.
public struct RetreatState: Sendable {
  public private(set) var isRetreated = false
  private var hidden: [Int32] = []
  private var front: Int32?

  public init() {}

  public mutating func toggle(running: [RunningApp], frontmost: Int32?) -> RetreatPlan {
    isRetreated ? restore(running: running) : retreat(running: running, frontmost: frontmost)
  }

  private mutating func retreat(running: [RunningApp], frontmost: Int32?) -> RetreatPlan {
    hidden = running.filter { $0.isRegular && !$0.isHidden && !$0.isSelf }.map(\.pid)
    front = frontmost.flatMap { hidden.contains($0) ? $0 : nil }
    isRetreated = true
    return RetreatPlan(hide: hidden)
  }

  private mutating func restore(running: [RunningApp]) -> RetreatPlan {
    let alive = Set(running.map(\.pid))
    let plan = RetreatPlan(unhide: hidden.filter { alive.contains($0) },
                           activate: front.flatMap { alive.contains($0) ? $0 : nil })
    hidden = []
    front = nil
    isRetreated = false
    return plan
  }
}
