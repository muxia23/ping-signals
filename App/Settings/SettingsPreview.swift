import AppKit
import PingCore
import SwiftUI

/// `--render-settings <dir>`: each settings tab and the onboarding window as PNGs, to review layout.
@MainActor
enum SettingsPreview {
  static func render(to dir: URL) {
    func model(_ edit: (inout PingCore.Settings) -> Void = { _ in }) -> SettingsModel {
      var s = PingCore.Settings()
      s.actions[.missing] = .shell("say $PING_ID")
      s.actions[.generic] = .open("https://github.com")
      edit(&s)
      return SettingsModel(settings: s, apply: { _ in }, tryAction: { _, _ in }, setRecording: { _ in })
    }
    let size = NSSize(width: 620, height: 560)
    write(TriggerTab(model: model()), size, dir, "1-trigger")
    write(WheelTab(model: model()), size, dir, "2-wheel-classic")
    write(WheelTab(model: model { $0.style = .modern }), size, dir, "2-wheel-modern")
    write(PingsSoundTab(model: model()), size, dir, "3-pings-sound")
    write(ActionsTab(model: model()), size, dir, "4-actions")
    write(GeneralTab(model: model { $0.language = .en }), size, dir, "5-general")
    // The real window, title bar and toolbar included, one PNG per tab.
    let controller = SettingsWindowController(model: model())
    controller.makeWindow()
    if let w = controller.window {
      w.setFrameOrigin(NSPoint(x: -10000, y: -10000))
      w.orderFrontRegardless()
      for (i, name) in ["trigger", "wheel", "pings-sound", "actions", "general"].enumerated() {
        controller.selectTab(i)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        snapshot(w, dir.appendingPathComponent("window-\(name).png"))
      }
    }
    write(OnboardingView(), NSSize(width: 440, height: 420), dir, "onboarding")
  }

  private static func snapshot(_ window: NSWindow, _ url: URL) {
    guard let frameView = window.contentView?.superview,
          let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
    frameView.cacheDisplay(in: frameView.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
  }

  private static func write<V: View>(_ view: V, _ size: NSSize, _ dir: URL, _ name: String) {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
      .background(Color(nsColor: .windowBackgroundColor)))
    host.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
  }
}
