import AppKit
import PingCore

/// Full-screen panels showing each covered screen's wallpaper, used by Retreat for screens whose
/// fullscreen app can't be hidden. They sit just below the ping overlay, so the wheel still works on top.
@MainActor
final class WallpaperCurtain {
  private var panels: [NSPanel] = []

  var isShown: Bool { !panels.isEmpty }

  /// Covers the screens currently filled by another app's fullscreen window.
  func coverFullscreenScreens() {
    let screens = NSScreen.screens
    let primaryHeight = screens.first?.frame.height ?? 0
    let globalRects = screens.map { ScreenMath.globalRect(ofScreenFrame: $0.frame, primaryHeight: primaryHeight) }
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let windows: [OnScreenWindow] = list.compactMap { w in
      guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
            let pid = w[kCGWindowOwnerPID as String] as? Int32,
            let dict = w[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: dict) else { return nil }
      return OnScreenWindow(pid: pid, bounds: bounds)
    }
    let me = ProcessInfo.processInfo.processIdentifier
    for i in CurtainPlan.screensToCover(screens: globalRects, windows: windows, selfPID: me) {
      panels.append(makePanel(for: screens[i]))
    }
  }

  func remove() {
    for p in panels { p.orderOut(nil) }
    panels = []
  }

  private func makePanel(for screen: NSScreen) -> NSPanel {
    let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    p.isOpaque = true
    p.hasShadow = false
    p.backgroundColor = .black
    let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
    view.wantsLayer = true
    if let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = NSImage(contentsOf: url) {
      view.layer?.contents = image
      view.layer?.contentsGravity = .resizeAspectFill
    }
    p.contentView = view
    p.setFrame(screen.frame, display: false)
    p.orderFrontRegardless()
    return p
  }
}
