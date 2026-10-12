import AppKit
import PingCore

/// Session-level CGEventTap feeding GestureMachine. Needs Accessibility permission.
@MainActor
final class EventTap {
  /// "LPIN" in eventSourceUserData marks events we post ourselves.
  private static let selfMarker: Int64 = 0x4C50_494E

  private let machine: GestureMachine
  private let onEmit: (GestureEmit) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var flags: UInt64 = 0
  private var watchdog: Timer?

  init(machine: GestureMachine, onEmit: @escaping (GestureEmit) -> Void) {
    self.machine = machine
    self.onEmit = onEmit
  }

  var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

  /// False when the tap can't be created (no Accessibility permission).
  func start() -> Bool {
    if tap != nil { return true }
    // No .mouseMoved: every gesture holds a button, so only *MouseDragged events matter, and skipping
    // plain moves keeps the app from waking on every pointer motion.
    let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                .keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      let me = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
      let swallow = MainActor.assumeIsolated { me.handle(type, event) }
      return swallow ? nil : Unmanaged.passUnretained(event)
    }
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: callback,
                                    userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
    tap = t
    source = CFMachPortCreateRunLoopSource(nil, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    resync()
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.resync()
        self.apply(self.machine.tick(nowMs: Self.nowMs()))
      }
    }
    RunLoop.main.add(timer, forMode: .common)  // keeps firing while a menu is tracking
    watchdog = timer
    return true
  }

  func stop() {
    watchdog?.invalidate()
    watchdog = nil
    if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
    if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
    if let t = tap { CFMachPortInvalidate(t) }
    tap = nil
    source = nil
  }

  /// Runs a machine call made outside the tap (config change, enable/disable) through the same output path.
  func apply(_ out: GestureOutput) {
    for e in out.emits { onEmit(e) }
    for r in out.replays {
      switch r {
      case .buttonDown(let b): post(b, down: true)
      case .buttonUp(let b): post(b, down: false)
      }
    }
  }

  // MARK: Tap

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
      resync()
      return false
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.selfMarker { return false }
    let t = Self.nowMs()
    feedFlags(event.flags.rawValue, t)
    if type == .flagsChanged { return false }

    if type == .keyDown || type == .keyUp {
      let vk = KeyMap.keyCodeToVK(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
      if vk == 0 { return false }
      return run(InputEvent(kind: type == .keyDown ? .keyDown : .keyUp, vk: vk, timeMs: t))
    }

    let loc = event.location
    var e = InputEvent(kind: .mouseMove, x: Int(loc.x.rounded()), y: Int(loc.y.rounded()), timeMs: t)
    switch type {
    // Dragged events always pass: dropping them at the session tap freezes the cursor.
    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: e.kind = .mouseMove
    case .leftMouseDown: e.kind = .mouseDown; e.button = .left
    case .leftMouseUp: e.kind = .mouseUp; e.button = .left
    case .rightMouseDown: e.kind = .mouseDown; e.button = .right
    case .rightMouseUp: e.kind = .mouseUp; e.button = .right
    case .otherMouseDown, .otherMouseUp:
      switch event.getIntegerValueField(.mouseEventButtonNumber) {
      case 2: e.button = .middle
      case 3: e.button = .x1
      case 4: e.button = .x2
      default: return false
      }
      e.kind = type == .otherMouseDown ? .mouseDown : .mouseUp
    default: return false
    }
    if e.kind == .mouseDown { machine.syncKeyStates(isDown: Self.isKeyDown) }
    let swallow = run(e)
    return e.kind == .mouseMove ? false : swallow
  }

  private func run(_ e: InputEvent) -> Bool {
    let out = machine.onEvent(e)
    apply(out)
    return out.swallow
  }

  /// Turns modifier-flag changes into the key events the machine expects. Mouse events carry flags too,
  /// which keeps the state right while Secure Event Input hides keyboard events from the tap.
  private func feedFlags(_ raw: UInt64, _ t: UInt64) {
    let f = raw & KeyMap.Flag.all
    guard f != flags else { return }
    for k in KeyMap.modifierTransitions(from: flags, to: f) {
      apply(machine.onEvent(InputEvent(kind: k.down ? .keyDown : .keyUp, vk: k.vk, timeMs: t)))
    }
    flags = f
  }

  private func resync() {
    feedFlags(CGEventSource.flagsState(.combinedSessionState).rawValue, Self.nowMs())
    machine.syncKeyStates(isDown: Self.isKeyDown)
  }

  private static let modifierVKs: Set<UInt32> = [VK.lShift, VK.rShift, VK.lControl, VK.rControl,
                                                 VK.lOption, VK.rOption, VK.lCommand, VK.rCommand]

  /// What the OS says about a key right now.
  private static func isKeyDown(_ vk: UInt32) -> Bool {
    if modifierVKs.contains(vk) { return KeyMap.modifierHeld(CGEventSource.flagsState(.combinedSessionState).rawValue, vk) }
    guard let code = KeyMap.vkToKeyCode(vk) else { return false }
    return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
  }

  private func post(_ b: MouseButton, down: Bool) {
    let type: CGEventType, button: CGMouseButton
    switch b {
    case .left: type = down ? .leftMouseDown : .leftMouseUp; button = .left
    case .right: type = down ? .rightMouseDown : .rightMouseUp; button = .right
    case .middle: type = down ? .otherMouseDown : .otherMouseUp; button = .center
    case .x1: type = down ? .otherMouseDown : .otherMouseUp; button = CGMouseButton(rawValue: 3)!
    case .x2: type = down ? .otherMouseDown : .otherMouseUp; button = CGMouseButton(rawValue: 4)!
    case .none: return
    }
    let pos = CGEvent(source: nil)?.location ?? .zero
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: button) else { return }
    e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    e.flags = CGEventFlags(rawValue: flags)       // a replayed ⌥-click keeps its ⌥
    e.setIntegerValueField(.eventSourceUserData, value: Self.selfMarker)
    e.post(tap: .cghidEventTap)
  }

  private static func nowMs() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }
}
