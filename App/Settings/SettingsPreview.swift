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
    // The todo panel with sample todos, empty and with the input chips set.
    let cal = Calendar.current, now = Date(), today = cal.startOfDay(for: now)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ping-preview-\(UUID().uuidString).json")
    let store = TodoStore(fileURL: file)
    func add(_ text: String, _ p: TodoPriority?, _ due: Date?, time: Bool = false, url: String? = nil, app: String? = nil,
             title: String? = nil, ago: TimeInterval) -> TodoItem? {
      store.add(text, context: TodoContext(appName: app, windowTitle: title, url: url), priority: p, due: due,
                dueHasTime: time, now: now.addingTimeInterval(-ago))
    }
    _ = add("交季度报告", .high, cal.date(bySettingHour: 18, minute: 0, second: 0, of: today), time: true,
            app: "Keynote", title: "Q3 复盘", ago: 3600 * 3)
    _ = add("回复客户邮件", .medium, cal.date(byAdding: .day, value: -1, to: today), app: "Mail", title: "Re: 报价", ago: 3600 * 26)
    _ = add("看一下 PR #42", .low, cal.date(byAdding: .day, value: 1, to: today), url: "https://github.com/muxia23/ping-signals/pull/42", ago: 600)
    _ = add("整理会议纪要", nil, cal.date(byAdding: .day, value: 6, to: today), app: "Notes", ago: 7200)
    _ = add("买咖啡豆", nil, nil, ago: 86400 * 2)
    if let done = add("订周五的机票", .medium, nil, ago: 86400) { store.toggleDone(done.id) }
    let draft = TodoDraft()
    draft.context = TodoContext(appName: "Dia", windowTitle: "ping-signals", url: "https://github.com/muxia23/ping-signals")
    let panelSize = NSSize(width: TodoPanelController.width, height: 640)
    write(TodoPanelView(draft: draft, store: store, onClose: {}, onOpenSource: { _ in }), panelSize, dir, "todo")
    let chips = TodoDraft()
    chips.text = "写周报"
    chips.priority = .high
    chips.due = cal.date(byAdding: .day, value: 1, to: today)
    chips.context = draft.context
    write(TodoPanelView(draft: chips, store: TodoStore(fileURL: file.appendingPathExtension("empty")), onClose: {},
                        onOpenSource: { _ in }), panelSize, dir, "todo-empty-chips")
    try? FileManager.default.removeItem(at: file)
    write(DueEditor(due: cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: today)!), hasTime: true) { _, _ in },
          NSSize(width: 256, height: 420), dir, "todo-due-editor")
    write(PriorityPicker(selection: .high) { _ in }, NSSize(width: 170, height: 150), dir, "todo-priority-picker")
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
