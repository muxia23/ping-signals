import AppKit
import QuartzCore
import PingCore

/// One transparent, click-through panel per screen, above fullscreen apps, on every Space.
/// A panel is on screen only while it shows a wheel or a ping. Panels are created deferred, so a screen-sized
/// backing store (tens of MB) is only allocated once a panel is first shown.
@MainActor
final class OverlayController {
  static let maxPings = 60

  @MainActor
  private final class Panel {
    let window: NSPanel
    let screenFrame: CGRect
    let backingScale: CGFloat
    let wheel = WheelLayer()
    let pings = CALayer()

    init(screen: NSScreen) {
      screenFrame = screen.frame
      backingScale = screen.backingScaleFactor
      window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false
      window.ignoresMouseEvents = true
      window.level = .screenSaver
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.wantsLayer = true
      view.layer?.addSublayer(pings)
      view.layer?.addSublayer(wheel.root)
      window.contentView = view
      window.setFrame(screen.frame, display: false)
    }

    func show() {
      if !window.isVisible { window.orderFrontRegardless() }
    }

    /// Orders the panel out once it shows neither a wheel nor a ping.
    func hideIfIdle() {
      if !wheel.isOpen && (pings.sublayers?.isEmpty ?? true) { window.orderOut(nil) }
    }
  }

  private var panels: [Panel] = []
  private var wheelPanel: Panel?
  private var art: WheelArt?
  private var observer: NSObjectProtocol?

  init() {
    rebuild()
    observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.rebuild() }
    }
  }

  func setWheelArt(_ art: WheelArt) {
    self.art = art
    for p in panels { p.wheel.setArt(art) }
  }

  private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

  private func rebuild() {
    for p in panels { p.window.orderOut(nil) }
    panels = NSScreen.screens.map { Panel(screen: $0) }
    wheelPanel = nil
    if let art { setWheelArt(art) }
  }

  private func panel(forGlobal g: GesturePoint) -> (Panel, CGPoint)? {
    let gp = CGPoint(x: g.x, y: g.y)
    let ph = primaryHeight
    guard let p = panels.first(where: { ScreenMath.globalRect(ofScreenFrame: $0.screenFrame, primaryHeight: ph).contains(gp) })
            ?? panels.first else { return nil }
    return (p, ScreenMath.localPoint(fromGlobal: gp, screenFrame: p.screenFrame, primaryHeight: primaryHeight))
  }

  private func local(_ g: GesturePoint, in p: Panel) -> CGPoint {
    ScreenMath.localPoint(fromGlobal: CGPoint(x: g.x, y: g.y), screenFrame: p.screenFrame, primaryHeight: primaryHeight)
  }

  func openWheel(at g: GesturePoint) {
    guard let (p, l) = panel(forGlobal: g) else { return }
    wheelPanel = p
    p.show()
    p.wheel.open(at: l)
  }

  /// True when a new slice became highlighted (for the tick sound).
  func moveWheel(to g: GesturePoint) -> Bool {
    guard let p = wheelPanel else { return false }
    return p.wheel.move(to: local(g, in: p))
  }

  /// The chosen slice and the wheel centre in global coordinates, or nil.
  func releaseWheel(at g: GesturePoint) -> (slice: Int, center: GesturePoint)? {
    guard let p = wheelPanel else { return nil }
    let center = p.wheel.center
    let slice = p.wheel.release(at: local(g, in: p))
    wheelPanel = nil
    p.hideIfIdle()
    guard let slice else { return nil }
    let a = CGPoint(x: center.x + p.screenFrame.minX, y: center.y + p.screenFrame.minY)
    let gc = ScreenMath.globalPoint(fromAppKit: a, primaryHeight: primaryHeight)
    return (slice, GesturePoint(Int(gc.x.rounded()), Int(gc.y.rounded())))
  }

  func cancelWheel() {
    wheelPanel?.wheel.close()
    wheelPanel?.hideIfIdle()
    wheelPanel = nil
  }

  func spawnPing(_ def: PingDef, style: WheelStyle, at g: GesturePoint, size: CGFloat, duration: Double) {
    guard let (p, l) = panel(forGlobal: g) else { return }
    while (p.pings.sublayers?.count ?? 0) >= Self.maxPings { p.pings.sublayers?.first?.removeFromSuperlayer() }
    p.show()
    let layer = style == .classic
      ? ClassicPingAnimator.spawn(def, at: l, size: size, duration: duration, scale: p.backingScale, in: p.pings)
      : ModernPingAnimator.spawn(def, at: l, size: size, duration: duration, scale: p.backingScale, in: p.pings)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(duration + 0.15))
      layer.removeFromSuperlayer()
      p.hideIfIdle()
    }
  }

  /// The centre of the screen under the mouse, in global coordinates (for preview pings).
  func mouseScreenCenter() -> GesturePoint {
    let mouse = NSEvent.mouseLocation
    let f = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens[0]).frame
    let g = ScreenMath.globalPoint(fromAppKit: CGPoint(x: f.midX, y: f.midY), primaryHeight: primaryHeight)
    return GesturePoint(Int(g.x), Int(g.y))
  }
}
