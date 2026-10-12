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
  private var tap: EventTap!
  private var menu: MenuBarController!
  private var tapRetry: Timer?
  private var screenObserver: NSObjectProtocol?

  init() {
    settings = store.load()
    tap = EventTap(machine: machine) { [weak self] e in self?.handle(e) }
    menu = MenuBarController(actions: .init(
      toggleEnabled: { [weak self] in self?.toggleEnabled() },
      setStyle: { [weak self] s in self?.setStyle(s) },
      preview: { [weak self] id in self?.preview(id) }))
    bus.register(PingEffectHandler(overlay: overlay, sound: sound) { [weak self] in self?.settings ?? Settings() })
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
    armTap(prompt: true)
  }

  // MARK: Event tap lifecycle

  private func armTap(prompt: Bool) {
    gate.waitForPermission(prompt: prompt) { [weak self] in self?.startTap() }
  }

  /// Starts the tap; if that fails although permission is granted, retries once a second.
  private func startTap() {
    tapRetry?.invalidate()
    tapRetry = nil
    refreshMenu()
    guard !tap.start() else { return }
    guard gate.isTrusted else { armTap(prompt: false); return }
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
    armTap(prompt: false)
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

  private func setStyle(_ s: WheelStyle) {
    settings.style = s
    store.save(settings)
    overlay.cancelWheel()
    refreshWheelArt()
    refreshMenu()
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
    menu.update(enabled: machine.enabled, style: settings.style, needsPermission: !gate.isTrusted)
  }
}
