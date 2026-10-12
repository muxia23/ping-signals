import AppKit
import PingCore

/// Danger: hide every visible background app and cover all screens with their wallpaper (which hides the
/// front app and any fullscreen window, neither of which macOS lets us hide). The next Danger lifts the
/// curtain and unhides exactly those apps; the front app never lost its place.
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
    let plan = state.toggle(running: running, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    var byPID: [Int32: NSRunningApplication] = [:]
    for a in apps { byPID[a.processIdentifier] = a }
    if state.isRetreated { curtain.coverAllScreens() } else { curtain.remove() }
    for pid in plan.hide { byPID[pid]?.hide() }
    for pid in plan.unhide { byPID[pid]?.unhide() }
  }
}
