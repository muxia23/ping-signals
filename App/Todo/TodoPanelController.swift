import AppKit
import SwiftUI
import PingCore

/// The todo panel sliding in from the right edge of a screen. It takes keyboard focus without
/// activating the app (like Spotlight), and closes on Esc or a click elsewhere.
@MainActor
final class TodoPanelController {
  private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
  }

  static let width: CGFloat = 360
  private let store: TodoStore
  private let draft = TodoDraft()
  private var panel: KeyPanel?
  private var outsideClickMonitor: Any?
  /// True while the slide-out runs; the panel is still visible until its completion orders it out.
  private var isHiding = false
  /// Increments per summon so a late browser URL only lands on the capture it belongs to.
  private var captureID = 0

  init(store: TodoStore) { self.store = store }

  var isVisible: Bool { (panel?.isVisible ?? false) && !isHiding }

  /// The id the next `show` will return.
  var nextCaptureID: Int { captureID + 1 }

  /// Shows the panel on `screen` with a fresh context. Returns the capture id for `updateURL`.
  @discardableResult
  func show(on screen: NSScreen, context: TodoContext) -> Int {
    captureID += 1
    draft.context = context
    draft.focusToken += 1
    let panel = self.panel ?? makePanel()
    self.panel = panel
    let visible = screen.visibleFrame
    let target = CGRect(x: visible.maxX - Self.width, y: visible.minY, width: Self.width, height: visible.height)
    if !panel.isVisible || isHiding {
      // Mid-hide: slide back from where it is, and cancel the pending orderOut.
      if !panel.isVisible { panel.setFrame(target.offsetBy(dx: Self.width, dy: 0), display: false) }
      isHiding = false
      panel.makeKeyAndOrderFront(nil)
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        panel.animator().setFrame(target, display: true)
      }
      if outsideClickMonitor == nil {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
          MainActor.assumeIsolated { self?.hide() }
        }
      }
    } else {
      panel.setFrame(target, display: true)
      panel.makeKeyAndOrderFront(nil)
    }
    return captureID
  }

  func updateURL(_ url: String, capture: Int) {
    guard capture == captureID else { return }
    draft.context.url = url
  }

  func hide() {
    guard let panel, panel.isVisible, !isHiding else { return }
    isHiding = true
    if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
    outsideClickMonitor = nil
    let off = panel.frame.offsetBy(dx: Self.width, dy: 0)
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.15
      panel.animator().setFrame(off, display: true)
    }, completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        // A show() during the slide-out cleared isHiding: keep the panel up.
        guard let self, self.isHiding else { return }
        self.isHiding = false
        panel.orderOut(nil)
      }
    })
  }

  private func makePanel() -> KeyPanel {
    let p = KeyPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 600),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    let blur = NSVisualEffectView()
    blur.material = .sidebar
    blur.blendingMode = .behindWindow
    blur.state = .active
    let host = NSHostingView(rootView: TodoPanelView(draft: draft, store: store,
                                                     onClose: { [weak self] in self?.hide() },
                                                     onOpenSource: { [weak self] in self?.openSource($0) }))
    host.translatesAutoresizingMaskIntoConstraints = false
    blur.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
      host.topAnchor.constraint(equalTo: blur.topAnchor),
      host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
    ])
    p.contentView = blur
    return p
  }

  /// Takes the user back: the page if there is one, else the app.
  private func openSource(_ item: TodoItem) {
    hide()
    if let s = item.url, let url = URL(string: s) {
      NSWorkspace.shared.open(url)
    } else if let id = item.bundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
  }
}
