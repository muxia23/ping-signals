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
  public init(hide: [Int32] = [], unhide: [Int32] = []) {
    self.hide = hide; self.unhide = unhide
  }
}

/// The Danger ping: the first press hides every visible background app, the next one brings back exactly
/// those. The front app is left alone — hiding it makes macOS promote, and so unhide, another app — and is
/// covered by the wallpaper curtain instead.
public struct RetreatState: Sendable {
  public private(set) var isRetreated = false
  private var hidden: [Int32] = []

  public init() {}

  public mutating func toggle(running: [RunningApp], frontmost: Int32?) -> RetreatPlan {
    if isRetreated {
      let alive = Set(running.map(\.pid))
      let plan = RetreatPlan(unhide: hidden.filter { alive.contains($0) })
      hidden = []
      isRetreated = false
      return plan
    }
    hidden = running.filter { $0.isRegular && !$0.isHidden && !$0.isSelf && $0.pid != frontmost }.map(\.pid)
    isRetreated = true
    return RetreatPlan(hide: hidden)
  }
}
