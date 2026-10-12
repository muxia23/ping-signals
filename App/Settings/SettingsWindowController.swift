import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
  let model: SettingsModel
  private var window: NSWindow?

  init(model: SettingsModel) { self.model = model }

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
      w.title = String(localized: "ping-signals Settings")
      w.styleMask = [.titled, .closable]
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
