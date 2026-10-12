import AppKit
import SwiftUI

/// Standard macOS settings window: icon tabs in the toolbar, the title follows the selected tab.
@MainActor
final class SettingsWindowController {
  let model: SettingsModel
  private var window: NSWindow?

  init(model: SettingsModel) { self.model = model }

  func show() {
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
    }
    model.settings.launchAtLogin = LaunchAtLogin.isEnabled   // the user may have changed it in System Settings
    model.refreshShortcuts()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}
