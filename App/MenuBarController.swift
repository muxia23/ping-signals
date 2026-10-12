import AppKit
import PingCore

@MainActor
final class MenuBarController: NSObject {
  struct Actions {
    var toggleEnabled: () -> Void
    var setStyle: (WheelStyle) -> Void
    var preview: (PingID) -> Void
    var openSettings: () -> Void
    var showOnboarding: () -> Void
  }

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let actions: Actions

  init(actions: Actions) {
    self.actions = actions
    super.init()
    item.button?.image = NSImage(systemSymbolName: "exclamationmark.bubble.fill", accessibilityDescription: "ping-signals")
  }

  /// Rebuilds the menu for the current state.
  func update(enabled: Bool, style: WheelStyle, needsPermission: Bool, toggleHotkey: Hotkey) {
    item.button?.appearsDisabled = !enabled || needsPermission
    let menu = NSMenu()
    if needsPermission {
      menu.addItem(entry("需要「辅助功能」权限… / Grant Accessibility…") { [actions] in actions.showOnboarding() })
      menu.addItem(.separator())
    }
    let toggle = entry(enabled ? "暂停 / Pause" : "启用 / Enable") { [actions] in actions.toggleEnabled() }
    if let key = KeyNames.menuKeyEquivalent(toggleHotkey.vk) {
      toggle.keyEquivalent = key
      var mask: NSEvent.ModifierFlags = []
      if toggleHotkey.mods.contains(.control) { mask.insert(.control) }
      if toggleHotkey.mods.contains(.option) { mask.insert(.option) }
      if toggleHotkey.mods.contains(.shift) { mask.insert(.shift) }
      if toggleHotkey.mods.contains(.command) { mask.insert(.command) }
      toggle.keyEquivalentModifierMask = mask
    }
    menu.addItem(toggle)

    let styleMenu = NSMenu()
    for (s, title) in [(WheelStyle.classic, "经典（2022）/ Classic"), (.modern, "新版 / Modern")] {
      let i = entry(title) { [actions] in actions.setStyle(s) }
      i.state = s == style ? .on : .off
      styleMenu.addItem(i)
    }
    let styleItem = NSMenuItem(title: "轮盘风格 / Wheel Style", action: nil, keyEquivalent: "")
    styleItem.submenu = styleMenu
    menu.addItem(styleItem)

    let previewMenu = NSMenu()
    let ids = PingCatalog.wheel(style: style, modernWheel: PingCatalog.defaultModernWheel) + [.generic]
    for id in ids { previewMenu.addItem(entry(id.rawValue) { [actions] in actions.preview(id) }) }
    let previewItem = NSMenuItem(title: "预览标记 / Preview Ping", action: nil, keyEquivalent: "")
    previewItem.submenu = previewMenu
    menu.addItem(previewItem)

    menu.addItem(.separator())
    let settingsItem = entry("设置… / Settings…") { [actions] in actions.openSettings() }
    settingsItem.keyEquivalent = ","
    menu.addItem(settingsItem)
    menu.addItem(.separator())
    menu.addItem(entry("退出 / Quit") { NSApp.terminate(nil) })
    item.menu = menu
  }

  private func entry(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
    let i = ClosureMenuItem(title: title, action: action)
    return i
  }
}

/// NSMenuItem that runs a closure.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
  private let run: () -> Void
  init(title: String, action: @escaping () -> Void) {
    run = action
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError("unused") }
  @objc private func fire() { run() }
}
