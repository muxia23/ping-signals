import AppKit
import PingCore

/// Is the topmost normal window under a global point a fullscreen app (a game)? Called only when a
/// gesture would start, so the window list query (~1 ms) never runs on ordinary clicks.
@MainActor
enum FullscreenProbe {
  static func isFullscreen(x: Int, y: Int) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
    let p = CGPoint(x: x, y: y)
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let screens = NSScreen.screens.map { ScreenMath.globalRect(ofScreenFrame: $0.frame, primaryHeight: primaryHeight) }
    for w in list {  // front to back
      guard (w[kCGWindowLayer as String] as? Int) == 0,
            let dict = w[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: dict),
            bounds.contains(p) else { continue }
      return screens.contains { abs($0.minX - bounds.minX) < 1 && abs($0.minY - bounds.minY) < 1
        && abs($0.width - bounds.width) < 1 && abs($0.height - bounds.height) < 1 }
    }
    return false
  }
}
