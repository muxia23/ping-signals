/// Decides what happens to every input event. Pure logic, ported from lolPing's decision.cpp
/// (single wheel, no Windows menu-key masking).
public final class GestureMachine {
  public enum State: Equatable, Sendable { case idle, pending, wheel, swallowUp }
  public static let watchdogMs: UInt64 = 10_000

  public private(set) var state: State = .idle
  public private(set) var enabled = true
  public private(set) var config = GestureConfig()
  /// Does a fullscreen app own the screen under (x, y)? Unset: gameCheck never fires.
  public var fullscreenProbe: ((Int, Int) -> Bool)?

  private var suspended = false
  private var keyDown = [Bool](repeating: false, count: 256)
  private var swallowKeyUps = Set<UInt32>()
  private var swallowRightUp = false
  /// A non-modifier key was pressed while the trigger is held (⌥+Tab, ⌘+Tab...): that chord belongs to
  /// another program, so clicks pass through until the trigger is released.
  private var foreignKey = false
  private var dragButton: MouseButton = .none
  private var px = 0, py = 0
  private var lastMouseMs: UInt64 = 0

  public init() {}

  // MARK: Configuration

  public func setConfig(_ c: GestureConfig) -> GestureOutput {
    var out = GestureOutput()
    cancelGesture(&out)
    config = c
    enabled = c.enabled
    return out
  }

  public func setEnabled(_ on: Bool) -> GestureOutput {
    var out = GestureOutput()
    if !on { cancelGesture(&out) }
    enabled = on
    return out
  }

  public func setSuspended(_ on: Bool) -> GestureOutput {
    var out = GestureOutput()
    if on { cancelGesture(&out) }
    suspended = on
    return out
  }

  public func tick(nowMs: UInt64) -> GestureOutput {
    var out = GestureOutput()
    let busy = state == .pending || state == .wheel
    if busy && nowMs > lastMouseMs && nowMs - lastMouseMs > Self.watchdogMs {
      out.emits.append(.cancel)
      // The press was swallowed, so its up must be swallowed too. If the up was really lost,
      // the next drag-button down resets swallowUp to idle.
      state = .swallowUp
    }
    return out
  }

  /// Forgets keys we believe are down but the OS says are up. Never marks a key as down.
  /// Keys whose down we swallowed are kept: the OS never saw them go down.
  public func syncKeyStates(isDown: (UInt32) -> Bool) {
    for vk in 0..<256 where keyDown[vk] && !swallowKeyUps.contains(UInt32(vk)) && !isDown(UInt32(vk)) {
      keyDown[vk] = false
    }
    if !held() { foreignKey = false }
  }

  // MARK: Events

  public func onEvent(_ e: InputEvent) -> GestureOutput {
    var out = GestureOutput()
    switch e.kind {
    case .keyDown: onKeyDown(e, &out)
    case .keyUp: onKeyUp(e, &out)
    case .mouseDown: lastMouseMs = e.timeMs; onMouseDown(e, &out)
    case .mouseUp: lastMouseMs = e.timeMs; onMouseUp(e, &out)
    case .mouseMove: lastMouseMs = e.timeMs; onMouseMove(e, &out)
    }
    return out
  }

  private func onKeyDown(_ e: InputEvent, _ out: inout GestureOutput) {
    let vk = e.vk & 0xFF
    let isRepeat = keyDown[Int(vk)]
    keyDown[Int(vk)] = true

    // Only in idle: a foreign key mid-gesture (Esc cancelling a wheel) says nothing about the next gesture.
    if state == .idle && Self.modBit(vk).isEmpty && !isTriggerVK(vk) && held() { foreignKey = true }

    if !suspended && vk == config.toggle.vk && mods() == config.toggle.mods {
      out.swallow = true
      swallowKeyUps.insert(vk)
      if !isRepeat {
        if enabled { cancelGesture(&out) }
        enabled.toggle()
        out.emits.append(.toggled(enabled))
      }
      return
    }
    if active {
      if vk == VK.escape && (state == .pending || state == .wheel) {
        out.swallow = true
        swallowKeyUps.insert(vk)
        cancelGesture(&out)
        return
      }
      // A custom-key trigger would type: keep it from the OS.
      if case .key(let k) = config.trigger, vk == k {
        out.swallow = true
        swallowKeyUps.insert(vk)
        return
      }
    }
    // This down passes through, so any pending up-swallow for the key is stale: drop it.
    swallowKeyUps.remove(vk)
  }

  private func onKeyUp(_ e: InputEvent, _ out: inout GestureOutput) {
    let vk = e.vk & 0xFF
    let heldBefore = held()
    keyDown[Int(vk)] = false
    if !held() { foreignKey = false }
    let triggerReleased = heldBefore && !held() && isTriggerVK(vk)

    if swallowKeyUps.remove(vk) != nil { out.swallow = true }
    guard triggerReleased else { return }
    if state == .pending {
      if config.clickPing {
        out.emits.append(.click(GesturePoint(px, py)))
        state = .swallowUp
      } else {
        // Plain click: re-press now; the real button-up will pass through.
        out.replays.append(.buttonDown(dragButton))
        state = .idle
      }
    } else if state == .wheel {
      out.emits.append(.cancel)
      state = .swallowUp
    }
  }

  private func onMouseDown(_ e: InputEvent, _ out: inout GestureOutput) {
    if state == .swallowUp && e.button == dragButton { state = .idle }  // the matching up was lost
    // A new right-down means the previous right-up never arrived: don't swallow this one's.
    if e.button == .right { swallowRightUp = false }
    guard active else { return }
    if (state == .pending || state == .wheel) && e.button == .right {
      out.swallow = true
      swallowRightUp = true
      cancelGesture(&out)
      return
    }
    guard state == .idle, !foreignKey, startsGesture(e.button) else { return }
    // Probed only when a gesture would actually start, so plain clicks never pay for the check.
    if config.gameCheck, let probe = fullscreenProbe, probe(e.x, e.y) { return }
    out.swallow = true
    state = .pending
    dragButton = e.button
    px = e.x
    py = e.y
  }

  private func onMouseUp(_ e: InputEvent, _ out: inout GestureOutput) {
    if e.button == .right && swallowRightUp {
      swallowRightUp = false
      out.swallow = true
      return
    }
    guard state != .idle, e.button == dragButton else { return }
    out.swallow = true
    if state == .pending {
      if config.clickPing {
        out.emits.append(.click(GesturePoint(px, py)))
      } else {
        out.replays.append(.buttonDown(dragButton))
        out.replays.append(.buttonUp(dragButton))
      }
    } else if state == .wheel {
      out.emits.append(.wheelRelease(GesturePoint(e.x, e.y)))
    }
    state = .idle
  }

  private func onMouseMove(_ e: InputEvent, _ out: inout GestureOutput) {
    if state == .pending {
      let dx = Double(e.x - px), dy = Double(e.y - py)
      if (dx * dx + dy * dy).squareRoot() > Double(config.dragThresholdPx) {
        state = .wheel
        out.emits.append(.wheelOpen(GesturePoint(px, py)))
        out.emits.append(.wheelMove(GesturePoint(e.x, e.y)))
      }
    } else if state == .wheel {
      out.emits.append(.wheelMove(GesturePoint(e.x, e.y)))
    }
  }

  // MARK: Helpers

  private var active: Bool { enabled && !suspended }

  private func cancelGesture(_ out: inout GestureOutput) {
    if state == .pending || state == .wheel {
      out.emits.append(.cancel)
      state = .swallowUp
    }
  }

  private static func modBit(_ vk: UInt32) -> Mods {
    switch vk {
    case VK.control, VK.lControl, VK.rControl: return .control
    case VK.option, VK.lOption, VK.rOption: return .option
    case VK.shift, VK.lShift, VK.rShift: return .shift
    case VK.lCommand, VK.rCommand: return .command
    default: return []
    }
  }

  private func mods() -> Mods {
    var m: Mods = []
    for vk in 0..<256 where keyDown[vk] { m.formUnion(Self.modBit(UInt32(vk))) }
    return m
  }

  /// Keyboard triggers only: a mouse trigger is never "held".
  private func held() -> Bool {
    switch config.trigger {
    case .option: return mods().contains(.option)
    case .control: return mods().contains(.control)
    case .shift: return mods().contains(.shift)
    case .command: return mods().contains(.command)
    case .key(let vk): return keyDown[Int(vk & 0xFF)]
    case .mouse4, .mouse5: return false
    }
  }

  private func isTriggerVK(_ vk: UInt32) -> Bool {
    switch config.trigger {
    case .option: return Self.modBit(vk) == .option
    case .control: return Self.modBit(vk) == .control
    case .shift: return Self.modBit(vk) == .shift
    case .command: return Self.modBit(vk) == .command
    case .key(let k): return vk == k
    case .mouse4, .mouse5: return false
    }
  }

  private func triggerButton() -> MouseButton {
    switch config.trigger {
    case .mouse4: return .x1
    case .mouse5: return .x2
    default: return .left
    }
  }

  /// A press starts a gesture: the side button of a mouse trigger, or the left button while the key is held.
  private func startsGesture(_ button: MouseButton) -> Bool {
    guard button == triggerButton() else { return false }
    switch config.trigger {
    case .mouse4, .mouse5: return true
    default: return held()
    }
  }
}
