import AppKit
import SwiftUI

/// Standard macOS settings window: icon tabs in the toolbar, the title follows the selected tab.
@MainActor
final class SettingsWindowController {
  let model: SettingsModel
  private(set) var window: NSWindow?
  private var tabs: NSTabViewController?
  private var closeObserver: NSObjectProtocol?

  init(model: SettingsModel) { self.model = model }

  func show() {
    makeWindow()
    model.settings.launchAtLogin = LaunchAtLogin.isEnabled   // the user may have changed it in System Settings
    model.refreshShortcuts()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func selectTab(_ index: Int) { tabs?.selectedTabViewItemIndex = index }

  func makeWindow() {
    if window == nil {
      let tabs = NSTabViewController()
      tabs.tabStyle = .toolbar
      func add(_ view: some View, _ title: String, _ symbol: String) {
        let vc = NSHostingController(rootView: view.frame(width: 620, height: 520))
        vc.sizingOptions = [.preferredContentSize]   // the window takes each tab's size
        vc.title = title                             // the toolbar tab controller shows it as the window title
        let item = NSTabViewItem(viewController: vc)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
      }
      add(TriggerTab(model: model), String(localized: "Trigger"), "cursorarrow.click.2")
      add(WheelTab(model: model), String(localized: "Wheel"), "circle.grid.cross")
      add(PingsSoundTab(model: model), String(localized: "Pings & Sound"), "speaker.wave.2")
      add(ActionsTab(model: model), String(localized: "Actions"), "bolt")
      add(GeneralTab(model: model), String(localized: "General"), "gearshape")
      let w = NSWindow(contentViewController: tabs)
      w.styleMask = [.titled, .closable]
      w.toolbarStyle = .preference
      w.isReleasedWhenClosed = false
      w.center()
      window = w
      self.tabs = tabs
      // Drop the window and its SwiftUI views once closed (tens of MB); the next show() rebuilds them.
      closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                             queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.releaseWindow() }
      }
    }
  }

  private func releaseWindow() {
    if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    closeObserver = nil
    // After the close completes: the window is still mid-close inside this notification.
    let w = window
    window = nil
    tabs = nil
    DispatchQueue.main.async { _ = w }
  }
}
