import AppKit
import PingCore

@MainActor
final class AppCoordinator {
  private let store = SettingsStore()
  private(set) var settings: Settings
  private let machine = GestureMachine()
  private let overlay = OverlayController()
  private let sound = SoundPlayer(names: PingCatalog.allSounds)
  private let bus = SignalBus()
  private let gate = AccessibilityGate()
  private let todoStore = TodoStore(fileURL: TodoStore.defaultURL)
  private lazy var todoPanel = TodoPanelController(store: todoStore)
  private let reminders = TodoReminders()
  private var tap: EventTap!
  private var runner: ActionRunner!
  private var menu: MenuBarController!
  private let onboarding = OnboardingWindowController()
  private var tapRetry: Timer?
  private var screenObserver: NSObjectProtocol?

  init() {
    settings = store.load()
    tap = EventTap(machine: machine) { [weak self] e in self?.handle(e) }
    menu = MenuBarController(actions: .init(
      toggleEnabled: { [weak self] in self?.toggleEnabled() },
      setStyle: { [weak self] s in self?.setStyle(s) },
      preview: { [weak self] id in self?.preview(id) },
      openSettings: { [weak self] in self?.openSettings() },
      showOnboarding: { [weak self] in self?.onboarding.show() }))
    bus.register(PingEffectHandler(overlay: overlay, sound: sound) { [weak self] in self?.settings ?? Settings() })
    runner = ActionRunner(retreat: RetreatAction(), todoPanel: TodoPanelAction(panel: todoPanel),
                          chatGPT: ChatGPTAction(), codex: CodexAction(), claude: ClaudeQuickEntryAction())
    bus.register(ActionRouter(runner: runner) { [weak self] in self?.settings.actions ?? PingActions.defaults })
    reminders.onOpen = { [weak self] in self?.showTodoPanel() }
    todoStore.onChange = { [weak self] items in self?.reminders.sync(items) }
    reminders.sync(todoStore.items)
    machine.fullscreenProbe = { x, y in MainActor.assumeIsolated { FullscreenProbe.isFullscreen(x: x, y: y) } }
    tap.apply(machine.setConfig(settings.gestureConfig(enabled: settings.enabledOnStart)))
    refreshWheelArt()
    // A new screen may have a different backing scale: re-render the wheel bitmaps.
    screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshWheelArt() }
    }
    refreshMenu()
    tap.onPermissionLost = { [weak self] in self?.permissionLost() }
    armTap(showGuide: true)
  }

  // MARK: Event tap lifecycle

  /// `showGuide`: open the onboarding window while waiting (not when permission was revoked later:
  /// the menu's "Grant Accessibility…" item opens it then).
  private func armTap(showGuide: Bool) {
    if showGuide && !gate.isTrusted { onboarding.show() }
    gate.waitForPermission { [weak self] in
      self?.onboarding.close()
      self?.startTap()
    }
  }

  /// Starts the tap; if that fails although permission is granted, retries once a second.
  private func startTap() {
    tapRetry?.invalidate()
    tapRetry = nil
    refreshMenu()
    guard !tap.start() else { return }
    guard gate.isTrusted else { armTap(showGuide: false); return }
    NSLog("ping-signals: event tap failed to start; retrying")
    let t = Timer(timeInterval: 1, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.startTap() }
    }
    RunLoop.main.add(t, forMode: .common)
    tapRetry = t
  }

  /// The tap has already stopped itself. Drop any gesture in progress and wait for a new grant.
  private func permissionLost() {
    NSLog("ping-signals: Accessibility permission revoked; event tap stopped")
    tap.apply(machine.setSuspended(true))   // cancels a pending/open wheel (emits .cancel)
    _ = machine.setSuspended(false)
    overlay.cancelWheel()
    refreshMenu()
    armTap(showGuide: false)
  }

  // MARK: Gesture output

  private var currentWheel: [PingID] { PingCatalog.wheel(style: settings.style, modernWheel: settings.wheel) }

  private func handle(_ e: GestureEmit) {
    switch e {
    case .wheelOpen(let p):
      overlay.openWheel(at: p)
      if !settings.muted { sound.warmUp() }
    case .wheelMove(let p):
      if overlay.moveWheel(to: p) && settings.tickSound && !settings.muted {
        sound.play(PingCatalog.tickSound, volume: Float(settings.volume) / 100)
      }
    case .wheelRelease(let p):
      if let r = overlay.releaseWheel(at: p), r.slice < currentWheel.count {
        emitSignal(currentWheel[r.slice], at: r.center, source: .wheel)
      }
    case .click(let p):
      emitSignal(PingCatalog.clickPing(style: settings.style, modernClickPing: settings.clickPingID), at: p, source: .click)
    case .cancel:
      overlay.cancelWheel()
    case .toggled:
      refreshMenu()
    }
  }

  private func emitSignal(_ id: PingID, at p: GesturePoint, source: PingSignal.Source) {
    bus.emit(PingSignal(ping: id, style: settings.style, point: p,
                        frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                        time: Date(), source: source))
  }

  // MARK: Menu actions

  private func toggleEnabled() {
    tap.apply(machine.setEnabled(!machine.enabled))
    refreshMenu()
  }

  /// The one place a settings change takes effect.
  func apply(_ new: Settings) {
    let old = settings
    guard new != old else { return }
    settings = new
    store.save(new)
    // Re-sending the config also cancels any gesture in progress (needed when the wheel changes).
    tap.apply(machine.setConfig(new.gestureConfig(enabled: machine.enabled)))
    overlay.cancelWheel()
    if new.style != old.style || new.wheel != old.wheel { refreshWheelArt() }
    if new.launchAtLogin != old.launchAtLogin { LaunchAtLogin.set(new.launchAtLogin) }
    onSettingsChanged?(new)
    refreshMenu()
  }

  /// Lets the settings window follow changes made elsewhere (e.g. the menu's style switch).
  var onSettingsChanged: ((Settings) -> Void)?

  private func setStyle(_ s: WheelStyle) {
    var new = settings
    new.style = s
    apply(new)
  }

  private lazy var settingsWindow: SettingsWindowController = {
    let model = SettingsModel(settings: settings,
      apply: { [weak self] in self?.apply($0) },
      tryAction: { [weak self] c, id in self?.tryAction(c, id) },
      setRecording: { [weak self] on in self?.setRecording(on) })
    onSettingsChanged = { [weak model] s in model?.settings = s }
    return SettingsWindowController(model: model)
  }()

  private func openSettings() { settingsWindow.show() }

  /// From a reminder: the panel on the main screen, without a fresh context.
  private func showTodoPanel() {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    todoPanel.show(on: screen, context: TodoContext())
  }

  /// Key recording must see the keys the gesture machine would otherwise act on (e.g. the pause shortcut).
  private func setRecording(_ on: Bool) { tap.apply(machine.setSuspended(on)) }

  private func tryAction(_ c: ActionConfig, _ id: PingID) {
    runner.run(c, signal: PingSignal(ping: id, style: settings.style, point: overlay.mouseScreenCenter(),
                                     frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                     time: Date(), source: .preview))
  }

  private func preview(_ id: PingID) {
    emitSignal(id, at: overlay.mouseScreenCenter(), source: .preview)
  }

  private func refreshWheelArt() {
    let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    let art = settings.style == .classic
      ? ClassicWheelRenderer.render(wheel: currentWheel, pixelScale: scale)
      : ModernWheelRenderer.render(wheel: currentWheel, pixelScale: scale)
    overlay.setWheelArt(art)
  }

  private func refreshMenu() {
    menu.update(enabled: machine.enabled, style: settings.style, needsPermission: !gate.isTrusted, toggleHotkey: settings.toggleHotkey)
  }
}
