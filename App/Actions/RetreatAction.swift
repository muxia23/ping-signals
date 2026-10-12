import AppKit
import PingCore

/// Danger: hide every visible app; the next Danger brings exactly those back. Fullscreen windows can't be
/// hidden (macOS refuses), so their screens are covered with the wallpaper instead.
@MainActor
final class RetreatAction: PingAction {
  private var state = RetreatState()
  private let curtain = WallpaperCurtain()

  func perform(_ signal: PingSignal) {
    let apps = NSWorkspace.shared.runningApplications
    let me = ProcessInfo.processInfo.processIdentifier
    let running = apps.map {
      RunningApp(pid: $0.processIdentifier, isRegular: $0.activationPolicy == .regular,
                 isHidden: $0.isHidden, isSelf: $0.processIdentifier == me)
    }
    let retreating = !state.isRetreated
    // Before hiding: a hidden app's fullscreen window no longer shows up as filling its screen.
    if retreating { curtain.coverFullscreenScreens() } else { curtain.remove() }
    let plan = state.toggle(running: running, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    var byPID: [Int32: NSRunningApplication] = [:]
    for a in apps { byPID[a.processIdentifier] = a }
    for pid in plan.hide { byPID[pid]?.hide() }
    for pid in plan.unhide { byPID[pid]?.unhide() }
    if let pid = plan.activate { byPID[pid]?.activate() }
  }
}
