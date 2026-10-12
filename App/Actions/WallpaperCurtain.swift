import AppKit

/// Panels showing each screen's wallpaper, covering every app window but staying below the Dock and the
/// menu bar, so a retreat looks like a clean desktop. The ping overlay sits above them, so the wheel still works.
@MainActor
final class WallpaperCurtain {
  /// Just below the Dock: above normal, floating and modal windows of the front app.
  private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
  private var panels: [NSPanel] = []

  func coverAllScreens() {
    remove()
    panels = NSScreen.screens.map(makePanel)
  }

  func remove() {
    for p in panels { p.orderOut(nil) }
    panels = []
  }

  private func makePanel(for screen: NSScreen) -> NSPanel {
    let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = Self.level
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
