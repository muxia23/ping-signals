/// Keys are identified by Windows virtual-key codes throughout PingCore, as in the original lolPing helper,
/// so its tests port unchanged. KeyMap translates macOS key codes and modifier flags into them.
public enum VK {
  public static let backspace: UInt32 = 0x08, tab: UInt32 = 0x09, enter: UInt32 = 0x0D
  public static let shift: UInt32 = 0x10, control: UInt32 = 0x11, option: UInt32 = 0x12
  public static let capsLock: UInt32 = 0x14, escape: UInt32 = 0x1B, space: UInt32 = 0x20
  public static let lShift: UInt32 = 0xA0, rShift: UInt32 = 0xA1
  public static let lControl: UInt32 = 0xA2, rControl: UInt32 = 0xA3
  public static let lOption: UInt32 = 0xA4, rOption: UInt32 = 0xA5
  public static let lCommand: UInt32 = 0x5B, rCommand: UInt32 = 0x5C
}

public struct KeyTransition: Equatable, Sendable {
  public let vk: UInt32
  public let down: Bool
  public init(vk: UInt32, down: Bool) { self.vk = vk; self.down = down }
}

public enum KeyMap {
  /// CGEventFlags bits: device-independent masks and the NX_DEVICE* left/right bits.
  public enum Flag {
    public static let shift: UInt64 = 0x0002_0000, control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000, command: UInt64 = 0x0010_0000
    public static let devLCtrl: UInt64 = 0x0001, devLShift: UInt64 = 0x0002, devRShift: UInt64 = 0x0004
    public static let devLCmd: UInt64 = 0x0008, devRCmd: UInt64 = 0x0010, devLAlt: UInt64 = 0x0020
    public static let devRAlt: UInt64 = 0x0040, devRCtrl: UInt64 = 0x2000
    /// Every bit modifierTransitions looks at.
    public static let all: UInt64 = shift | control | option | command | devLCtrl | devLShift | devRShift
      | devLCmd | devRCmd | devLAlt | devRAlt | devRCtrl
  }

  /// kVK_* (Carbon Events.h) → VK. Modifiers are listed so vkToKeyCode can answer for them.
  private static let keys: [(code: UInt16, vk: UInt32)] = [
    (0x00, 0x41), (0x0B, 0x42), (0x08, 0x43), (0x02, 0x44), (0x0E, 0x45), (0x03, 0x46), (0x05, 0x47), (0x04, 0x48),
    (0x22, 0x49), (0x26, 0x4A), (0x28, 0x4B), (0x25, 0x4C), (0x2E, 0x4D), (0x2D, 0x4E), (0x1F, 0x4F), (0x23, 0x50),
    (0x0C, 0x51), (0x0F, 0x52), (0x01, 0x53), (0x11, 0x54), (0x20, 0x55), (0x09, 0x56), (0x0D, 0x57), (0x07, 0x58),
    (0x10, 0x59), (0x06, 0x5A),
    (0x1D, 0x30), (0x12, 0x31), (0x13, 0x32), (0x14, 0x33), (0x15, 0x34), (0x17, 0x35), (0x16, 0x36), (0x1A, 0x37),
    (0x1C, 0x38), (0x19, 0x39),
    (0x7A, 0x70), (0x78, 0x71), (0x63, 0x72), (0x76, 0x73), (0x60, 0x74), (0x61, 0x75), (0x62, 0x76),
    (0x64, 0x77), (0x65, 0x78), (0x6D, 0x79), (0x67, 0x7A), (0x6F, 0x7B), (0x69, 0x7C), (0x6B, 0x7D),
    (0x71, 0x7E), (0x6A, 0x7F), (0x40, 0x80), (0x4F, 0x81), (0x50, 0x82), (0x5A, 0x83),  // F1-F20
    (0x24, 0x0D), (0x4C, 0x0D),                                                          // Return, keypad Enter
    (0x30, 0x09), (0x31, 0x20), (0x33, 0x08), (0x35, 0x1B), (0x75, 0x2E), (0x72, 0x2D),  // Tab Space ⌫ Esc ⌦ Help
    (0x73, 0x24), (0x77, 0x23), (0x74, 0x21), (0x79, 0x22),                              // Home End PgUp PgDn
    (0x7B, 0x25), (0x7E, 0x26), (0x7C, 0x27), (0x7D, 0x28),                              // arrows
    (0x32, 0xC0), (0x1B, 0xBD), (0x18, 0xBB), (0x21, 0xDB), (0x1E, 0xDD), (0x2A, 0xDC),  // ` - = [ ] backslash
    (0x29, 0xBA), (0x27, 0xDE), (0x2B, 0xBC), (0x2F, 0xBE), (0x2C, 0xBF),                // ; ' , . /
    (0x52, 0x60), (0x53, 0x61), (0x54, 0x62), (0x55, 0x63), (0x56, 0x64), (0x57, 0x65), (0x58, 0x66),
    (0x59, 0x67), (0x5B, 0x68), (0x5C, 0x69),                                            // keypad 0-9
    (0x43, 0x6A), (0x45, 0x6B), (0x4E, 0x6D), (0x41, 0x6E), (0x4B, 0x6F),                // keypad * + - . /
    (0x39, 0x14),                                                                        // Caps Lock
    (0x38, 0xA0), (0x3C, 0xA1), (0x3B, 0xA2), (0x3E, 0xA3), (0x3A, 0xA4), (0x3D, 0xA5),  // modifiers
    (0x37, 0x5B), (0x36, 0x5C),
  ]

  private struct Modifier { let vk: UInt32; let group: UInt64; let mine: UInt64; let other: UInt64 }
  private static let modifiers: [Modifier] = [
    Modifier(vk: VK.lShift, group: Flag.shift, mine: Flag.devLShift, other: Flag.devRShift),
    Modifier(vk: VK.rShift, group: Flag.shift, mine: Flag.devRShift, other: Flag.devLShift),
    Modifier(vk: VK.lControl, group: Flag.control, mine: Flag.devLCtrl, other: Flag.devRCtrl),
    Modifier(vk: VK.rControl, group: Flag.control, mine: Flag.devRCtrl, other: Flag.devLCtrl),
    Modifier(vk: VK.lOption, group: Flag.option, mine: Flag.devLAlt, other: Flag.devRAlt),
    Modifier(vk: VK.rOption, group: Flag.option, mine: Flag.devRAlt, other: Flag.devLAlt),
    Modifier(vk: VK.lCommand, group: Flag.command, mine: Flag.devLCmd, other: Flag.devRCmd),
    Modifier(vk: VK.rCommand, group: Flag.command, mine: Flag.devRCmd, other: Flag.devLCmd),
  ]

  /// macOS key code → VK; 0 when the key has no VK equivalent.
  public static func keyCodeToVK(_ code: UInt16) -> UInt32 {
    keys.first { $0.code == code }?.vk ?? 0
  }

  /// VK → macOS key code; nil when there is none.
  public static func vkToKeyCode(_ vk: UInt32) -> UInt16? {
    keys.first { $0.vk == vk }?.code
  }

  /// Whether modifier key `vk` is held according to `flags`. Synthetic events often carry only the
  /// device-independent mask: that counts as the left key.
  public static func modifierHeld(_ flags: UInt64, _ vk: UInt32) -> Bool {
    guard let m = modifiers.first(where: { $0.vk == vk }) else { return false }
    if flags & m.group == 0 { return false }
    if flags & m.mine != 0 { return true }
    let isLeft = vk == VK.lShift || vk == VK.lControl || vk == VK.lOption || vk == VK.lCommand
    return isLeft && flags & m.other == 0
  }

  /// The modifier key-ups, then key-downs, that turn `old` into `new`.
  public static func modifierTransitions(from old: UInt64, to new: UInt64) -> [KeyTransition] {
    var ups: [KeyTransition] = [], downs: [KeyTransition] = []
    for m in modifiers {
      let was = modifierHeld(old, m.vk), now = modifierHeld(new, m.vk)
      if was && !now { ups.append(KeyTransition(vk: m.vk, down: false)) }
      if !was && now { downs.append(KeyTransition(vk: m.vk, down: true)) }
    }
    return ups + downs
  }
}
