import Testing
@testable import PingCore

private let ALT = VK.lOption, CTRL = VK.lControl, CMD = VK.lCommand
private let KEY_P: UInt32 = 0x50, KEY_V: UInt32 = 0x56, ESC = VK.escape, TAB = VK.tab

private func kd(_ vk: UInt32) -> InputEvent { InputEvent(kind: .keyDown, vk: vk) }
private func ku(_ vk: UInt32) -> InputEvent { InputEvent(kind: .keyUp, vk: vk) }
private func md(_ b: MouseButton, _ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseDown, button: b, x: x, y: y, timeMs: t) }
private func mu(_ b: MouseButton, _ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseUp, button: b, x: x, y: y, timeMs: t) }
private func mv(_ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseMove, x: x, y: y, timeMs: t) }

private func machine(_ trigger: Trigger = .option, clickPing: Bool = false, gameCheck: Bool = false) -> GestureMachine {
  var c = GestureConfig()
  c.trigger = trigger
  c.clickPing = clickPing
  c.gameCheck = gameCheck
  let m = GestureMachine()
  _ = m.setConfig(c)
  return m
}

/// ⌥ held, left pressed at (100,100), dragged to (130,100): the wheel is open.
private func openWheel(_ m: GestureMachine) {
  _ = m.onEvent(kd(ALT)); _ = m.onEvent(md(.left, 100, 100)); _ = m.onEvent(mv(130, 100))
}

private func hasCancel(_ o: GestureOutput) -> Bool { o.emits.contains(.cancel) }
private func clickPoint(_ o: GestureOutput) -> GesturePoint? {
  for e in o.emits { if case .click(let p) = e { return p } }
  return nil
}
private func releasePoint(_ o: GestureOutput) -> GesturePoint? {
  for e in o.emits { if case .wheelRelease(let p) = e { return p } }
  return nil
}
private func opened(_ o: GestureOutput) -> Bool {
  o.emits.contains { if case .wheelOpen = $0 { return true } else { return false } }
}

@Suite struct GestureMachineTests {
  @Test func altDragOpensWheelAndReleases() {
    let m = GestureMachine()
    #expect(!m.onEvent(kd(ALT)).swallow)
    var r = m.onEvent(md(.left, 100, 100))
    #expect(r.swallow)
    #expect(m.state == .pending)
    r = m.onEvent(mv(104, 104))  // 5.7 px, below the 8 px threshold
    #expect(!r.swallow && r.emits.isEmpty)
    r = m.onEvent(mv(120, 100))
    #expect(!r.swallow)
    #expect(m.state == .wheel)
    #expect(r.emits == [.wheelOpen(GesturePoint(100, 100)), .wheelMove(GesturePoint(120, 100))])
    r = m.onEvent(mv(125, 90))
    #expect(r.emits == [.wheelMove(GesturePoint(125, 90))])
    r = m.onEvent(mu(.left, 130, 90))
    #expect(r.swallow)
    #expect(releasePoint(r) == GesturePoint(130, 90))
    #expect(m.state == .idle)
  }

  @Test func plainClickPassesThrough() {
    let m = GestureMachine()
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(!m.onEvent(mu(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func altClickReplaysWhenClickPingOff() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(md(.left, 50, 60)).swallow)
    _ = m.onEvent(mv(53, 62))  // tiny jitter, still a click
    let r = m.onEvent(mu(.left, 53, 62))
    #expect(r.swallow)
    #expect(r.emits.isEmpty)
    #expect(r.replays == [.buttonDown(.left), .buttonUp(.left)])
    #expect(m.state == .idle)
  }

  @Test func altClickPingsWhenClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 50, 60))
    let r = m.onEvent(mu(.left, 51, 60))
    #expect(r.swallow)
    #expect(r.replays.isEmpty)
    #expect(clickPoint(r) == GesturePoint(50, 60))
  }

  @Test func rightClickCancelsWheel() {
    let m = GestureMachine()
    openWheel(m)
    var r = m.onEvent(md(.right, 130, 100))
    #expect(r.swallow)
    #expect(hasCancel(r))
    #expect(m.onEvent(mu(.right, 130, 100)).swallow)
    r = m.onEvent(mu(.left, 130, 100))
    #expect(r.swallow)
    #expect(releasePoint(r) == nil)
    #expect(m.state == .idle)
  }

  @Test func rightClickWithAltButNoGesturePasses() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(md(.right, 1, 1)).swallow)
    #expect(!m.onEvent(mu(.right, 1, 1)).swallow)
  }

  @Test func escapeCancelsWheel() {
    let m = GestureMachine()
    openWheel(m)
    var r = m.onEvent(kd(ESC))
    #expect(r.swallow)
    #expect(hasCancel(r))
    #expect(m.onEvent(ku(ESC)).swallow)
    r = m.onEvent(mu(.left, 130, 100))
    #expect(r.swallow && r.emits.isEmpty)
  }

  @Test func triggerReleasedDuringWheelCancels() {
    let m = GestureMachine()
    openWheel(m)
    let r = m.onEvent(ku(ALT))
    #expect(hasCancel(r))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func triggerReleasedDuringPendingReplaysPress() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100))
    let r = m.onEvent(ku(ALT))
    #expect(!r.swallow)  // macOS has no menu-key mask: the ⌥-up passes
    #expect(r.replays == [.buttonDown(.left)])
    #expect(m.state == .idle)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)  // the real up completes the replayed click
  }

  @Test func triggerReleasedDuringPendingPingsWhenClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100))
    let r = m.onEvent(ku(ALT))
    #expect(clickPoint(r) == GesturePoint(100, 100))
    #expect(m.onEvent(mu(.left, 100, 100)).swallow)
  }

  /// ⌥+Tab belongs to another program: clicks pass while the chord lasts.
  @Test func altTabClicksPassThrough() {
    let m = GestureMachine()
    #expect(!m.onEvent(kd(ALT)).swallow)
    #expect(!m.onEvent(kd(TAB)).swallow)
    #expect(!m.onEvent(ku(TAB)).swallow)
    var r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    r = m.onEvent(ku(ALT))
    #expect(!r.swallow && r.replays.isEmpty)
    _ = m.onEvent(kd(ALT))  // the chord is over: ⌥+click gestures again
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow)
    #expect(r.replays.count == 2)
  }

  @Test func altTabClickPlacesNoPingEvenWithClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(kd(TAB))
    let r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    let up = m.onEvent(ku(ALT))
    #expect(!up.swallow && up.replays.isEmpty)
  }

  @Test func plainAltTapIsUntouched() {
    let m = GestureMachine()
    #expect(!m.onEvent(kd(ALT)).swallow)
    let r = m.onEvent(ku(ALT))
    #expect(!r.swallow && r.replays.isEmpty && r.emits.isEmpty)
  }

  @Test func dragThresholdIsStrictlyGreater() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100))
    #expect(m.onEvent(mv(108, 100)).emits.isEmpty)  // exactly 8 px: still a click
    #expect(m.state == .pending)
    #expect(opened(m.onEvent(mv(109, 100))))       // 9 px opens the wheel
  }

  @Test func commandTabClicksPassAndSyncClearsFlag() {
    let m = machine(.command)
    _ = m.onEvent(kd(CMD))
    _ = m.onEvent(kd(TAB))
    #expect(!m.onEvent(md(.left, 100, 100)).swallow)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    m.syncKeyStates { _ in false }  // the OS reports every key up
    _ = m.onEvent(kd(CMD))
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
  }

  @Test func fullscreenGameKeepsTheClick() {
    let m = machine(clickPing: true, gameCheck: true)
    var fullscreen = true
    m.fullscreenProbe = { _, _ in fullscreen }
    _ = m.onEvent(kd(ALT))
    var r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    fullscreen = false
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow)
    #expect(clickPoint(r) != nil)
    #expect(m.state == .idle)
  }

  @Test func fullscreenProbeIgnoredWhenDisabled() {
    let m = machine(clickPing: true, gameCheck: false)
    var consulted = false
    m.fullscreenProbe = { _, _ in consulted = true; return true }
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    #expect(!consulted)
    #expect(clickPoint(m.onEvent(mu(.left, 100, 100))) != nil)
  }

  @Test func altUpAfterGestureIsNotTouched() {
    let m = GestureMachine()
    openWheel(m)
    _ = m.onEvent(mu(.left, 130, 100))
    let r = m.onEvent(ku(ALT))
    #expect(!r.swallow && r.replays.isEmpty)
  }

  @Test func toggleHotkeyDisablesAndEnables() {
    let m = GestureMachine()
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    var r = m.onEvent(kd(KEY_P))
    #expect(r.swallow)
    #expect(r.emits == [.toggled(false)])
    #expect(!m.enabled)
    #expect(m.onEvent(ku(KEY_P)).swallow)
    _ = m.onEvent(ku(CTRL))
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)  // disabled: ⌥+press passes
    _ = m.onEvent(mu(.left, 1, 1))
    _ = m.onEvent(kd(CTRL))
    r = m.onEvent(kd(KEY_P))
    #expect(r.emits == [.toggled(true)])
    #expect(m.enabled)
  }

  @Test func hotkeyAutorepeatTogglesOnce() {
    let m = GestureMachine()
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(kd(KEY_P)).emits == [.toggled(false)])
    let repeatOut = m.onEvent(kd(KEY_P))
    #expect(repeatOut.swallow)
    #expect(repeatOut.emits.isEmpty)
    #expect(!m.enabled)
  }

  @Test func hotkeyIgnoredWhileSuspended() {
    let m = GestureMachine()
    _ = m.setSuspended(true)
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    let r = m.onEvent(kd(KEY_P))
    #expect(!r.swallow && r.emits.isEmpty)
    #expect(m.enabled)
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
  }

  @Test func disablingMidDragCancelsAndSwallowsUp() {
    let m = GestureMachine()
    openWheel(m)
    #expect(hasCancel(m.setEnabled(false)))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func configChangeMidDragCancels() {
    let m = GestureMachine()
    openWheel(m)
    #expect(hasCancel(m.setConfig(GestureConfig())))
    #expect(m.state == .swallowUp)
  }

  @Test func lostUpRecoversOnNextPress() {
    let m = GestureMachine()
    openWheel(m)
    _ = m.setEnabled(false)
    _ = m.setEnabled(true)
    #expect(m.onEvent(md(.left, 5, 5)).swallow)  // ⌥ still held
    #expect(m.state == .pending)
  }

  @Test func lostRightUpDoesNotSwallowNextClick() {
    let m = GestureMachine()
    openWheel(m)
    #expect(m.onEvent(md(.right, 130, 100)).swallow)
    _ = m.onEvent(mu(.left, 130, 100))
    #expect(m.state == .idle)
    #expect(!m.onEvent(md(.right, 5, 5)).swallow)
    #expect(!m.onEvent(mu(.right, 5, 5)).swallow)
  }

  @Test func lostKeyUpDoesNotSwallowNextPress() {
    let m = GestureMachine()
    openWheel(m)
    #expect(m.onEvent(kd(ESC)).swallow)
    _ = m.onEvent(mu(.left, 130, 100))
    _ = m.onEvent(ku(ALT))
    #expect(m.state == .idle)
    #expect(!m.onEvent(kd(ESC)).swallow)
    #expect(!m.onEvent(ku(ESC)).swallow)
  }

  @Test func buttonHeldBeforeTriggerPassesUp() {
    let m = GestureMachine()
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(mv(50, 50)).swallow)
    #expect(!m.onEvent(mu(.left, 50, 50)).swallow)
    #expect(m.state == .idle)
  }

  @Test func watchdogCancelsStaleGesture() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100, 1000))
    _ = m.onEvent(mv(130, 100, 1100))
    #expect(m.tick(nowMs: 5000).emits.isEmpty)
    #expect(hasCancel(m.tick(nowMs: 1100 + GestureMachine.watchdogMs + 1)))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func watchdogFromPendingSwallowsLaterUp() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100, 1000))
    #expect(m.state == .pending)
    #expect(m.tick(nowMs: 1000 + GestureMachine.watchdogMs).emits.isEmpty)  // exactly at the limit
    #expect(hasCancel(m.tick(nowMs: 1000 + GestureMachine.watchdogMs + 1)))
    #expect(m.state == .swallowUp)
    let r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow && r.emits.isEmpty && r.replays.isEmpty)
    #expect(m.state == .idle)
  }

  @Test func syncClearsStaleTrigger() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    m.syncKeyStates { _ in false }
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func syncKeepsKeysThatAreStillDown() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    m.syncKeyStates { $0 == ALT }
    #expect(m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .pending)
  }

  @Test func syncNeverSetsKeys() {
    let m = GestureMachine()
    m.syncKeyStates { _ in true }
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func syncKeepsSwallowedTriggerKey() {
    let m = machine(.key(KEY_V))
    #expect(m.onEvent(kd(KEY_V)).swallow)
    m.syncKeyStates { _ in false }  // the OS never saw V go down
    #expect(m.onEvent(md(.left, 0, 0)).swallow)
    #expect(m.state == .pending)
  }

  @Test func controlTriggerIgnoresOption() {
    let m = machine(.control)
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    _ = m.onEvent(mu(.left, 1, 1))
    _ = m.onEvent(ku(ALT))
    _ = m.onEvent(kd(CTRL))
    #expect(m.onEvent(md(.left, 1, 1)).swallow)
  }

  @Test func customKeyTrigger() {
    let m = machine(.key(KEY_V))
    #expect(m.onEvent(kd(KEY_V)).swallow)
    #expect(m.onEvent(md(.left, 0, 0)).swallow)
    #expect(opened(m.onEvent(mv(0, 40))))
    #expect(releasePoint(m.onEvent(mu(.left, 0, 40))) != nil)
    #expect(m.onEvent(ku(KEY_V)).swallow)
    _ = m.setEnabled(false)
    #expect(!m.onEvent(kd(KEY_V)).swallow)  // disabled: typing V works again
  }

  @Test func mouse4TriggerDragsWithSideButton() {
    let m = machine(.mouse4)
    #expect(!m.onEvent(md(.left, 0, 0)).swallow)
    _ = m.onEvent(mu(.left, 0, 0))
    #expect(m.onEvent(md(.x1, 10, 10)).swallow)
    let r = m.onEvent(mu(.x1, 10, 10))  // click without drag: replay so browser Back still works
    #expect(r.swallow)
    #expect(r.replays == [.buttonDown(.x1), .buttonUp(.x1)])
    _ = m.onEvent(md(.x1, 10, 10))
    #expect(opened(m.onEvent(mv(40, 10))))
    #expect(releasePoint(m.onEvent(mu(.x1, 40, 10))) != nil)
  }

  @Test func optionDragThroughFlagTransitions() {
    // EventTap feeds flag transitions to the machine as key events: ⌥ + drag must open the wheel.
    let m = GestureMachine()
    for t in KeyMap.modifierTransitions(from: 0, to: KeyMap.Flag.option | KeyMap.Flag.devLAlt) {
      _ = m.onEvent(t.down ? kd(t.vk) : ku(t.vk))
    }
    #expect(m.onEvent(md(.left, 10, 10)).swallow)
    #expect(opened(m.onEvent(mv(40, 10))))
  }
}
