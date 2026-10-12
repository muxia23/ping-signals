import AppKit
import PingCore

/// Danger: hide every visible app; the next Danger brings exactly those back.
@MainActor
final class RetreatAction: PingAction {
  private var state = RetreatState()

  func perform(_ signal: PingSignal) {
    let apps = NSWorkspace.shared.runningApplications
    let me = ProcessInfo.processInfo.processIdentifier
    let running = apps.map {
      RunningApp(pid: $0.processIdentifier, isRegular: $0.activationPolicy == .regular,
                 isHidden: $0.isHidden, isSelf: $0.processIdentifier == me)
    }
    let plan = state.toggle(running: running, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    var byPID: [Int32: NSRunningApplication] = [:]
    for a in apps { byPID[a.processIdentifier] = a }
    for pid in plan.hide { byPID[pid]?.hide() }
    for pid in plan.unhide { byPID[pid]?.unhide() }
    if let pid = plan.activate { byPID[pid]?.activate() }
  }
}
