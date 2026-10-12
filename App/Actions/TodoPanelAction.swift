import AppKit
import PingCore

/// On My Way: slide in the todo panel on the ping's screen, with the current app, window and page attached.
@MainActor
final class TodoPanelAction: PingAction {
  private let panel: TodoPanelController

  init(panel: TodoPanelController) { self.panel = panel }

  func perform(_ signal: PingSignal) {
    // The id show() will return, fixed now so a late URL can't land on a later summon.
    let capture = panel.nextCaptureID
    // Capture before showing: once the panel has focus, the front app context is ours.
    let context = ContextCapture.capture { [weak self] url in self?.panel.updateURL(url, capture: capture) }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let p = ScreenMath.appKitPoint(fromGlobal: CGPoint(x: signal.point.x, y: signal.point.y), primaryHeight: primaryHeight)
    let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    panel.show(on: screen, context: context)
  }
}
