import AppKit
import PingCore

/// Keyboard events this app posts. They carry `marker`, so our own EventTap lets them through untouched.
@MainActor
enum SyntheticInput {
  /// "LPIN" in eventSourceUserData.
  static let marker: Int64 = 0x4C50_494E

  /// Runs `body` once no modifier key is physically held (at most 2 s later). A ping fires while ⌥ is
  /// still down from the gesture; synthetic modifier taps sent then would merge with the real key.
  static func whenModifiersReleased(_ body: @escaping @MainActor () async -> Void) {
    Task { @MainActor in
      let mods = KeyMap.Flag.shift | KeyMap.Flag.control | KeyMap.Flag.option | KeyMap.Flag.command
      var waited = 0
      while CGEventSource.flagsState(.hidSystemState).rawValue & mods != 0 && waited < 2000 {
        try? await Task.sleep(for: .milliseconds(30))
        waited += 30
      }
      await body()
    }
  }

  /// Two quick taps of the left Option key: Claude desktop's default Quick Entry shortcut.
  static func doubleTapOption() async {
    postOption(down: true)
    try? await Task.sleep(for: .milliseconds(40))
    postOption(down: false)
    try? await Task.sleep(for: .milliseconds(90))
    postOption(down: true)
    try? await Task.sleep(for: .milliseconds(40))
    postOption(down: false)
  }

  private static func postOption(down: Bool) {
    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0x3A, keyDown: down) else { return }  // kVK_Option
    e.type = .flagsChanged
    let nonCoalesced: UInt64 = 0x100
    e.flags = CGEventFlags(rawValue: down ? KeyMap.Flag.option | KeyMap.Flag.devLAlt | nonCoalesced : nonCoalesced)
    e.setIntegerValueField(.eventSourceUserData, value: marker)
    e.post(tap: .cghidEventTap)
  }

  /// Presses and releases `hotkey` (call after `whenModifiersReleased`).
  static func press(_ hotkey: Hotkey) {
    guard let code = KeyMap.vkToKeyCode(hotkey.vk) else { return }
    var flags: UInt64 = 0
    if hotkey.mods.contains(.control) { flags |= KeyMap.Flag.control }
    if hotkey.mods.contains(.option) { flags |= KeyMap.Flag.option }
    if hotkey.mods.contains(.shift) { flags |= KeyMap.Flag.shift }
    if hotkey.mods.contains(.command) { flags |= KeyMap.Flag.command }
    for down in [true, false] {
      guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
      e.flags = CGEventFlags(rawValue: flags)
      e.setIntegerValueField(.eventSourceUserData, value: marker)
      e.post(tap: .cghidEventTap)
    }
  }
}
