/// Display names for VK codes and hotkeys, in macOS style (⌃⌥⇧⌘ order).
public enum KeyNames {
  private static let special: [UInt32: String] = [
    0x0D: "↩", 0x09: "⇥", 0x20: "Space", 0x08: "⌫", 0x1B: "⎋", 0x2E: "⌦", 0x2D: "Help", 0x14: "⇪",
    0x24: "↖", 0x23: "↘", 0x21: "⇞", 0x22: "⇟", 0x25: "←", 0x26: "↑", 0x27: "→", 0x28: "↓",
    0xC0: "`", 0xBD: "-", 0xBB: "=", 0xDB: "[", 0xDD: "]", 0xDC: "\\", 0xBA: ";", 0xDE: "'",
    0xBC: ",", 0xBE: ".", 0xBF: "/", 0x6A: "Num*", 0x6B: "Num+", 0x6D: "Num-", 0x6E: "Num.", 0x6F: "Num/",
    VK.lShift: "Left ⇧", VK.rShift: "Right ⇧", VK.lControl: "Left ⌃", VK.rControl: "Right ⌃",
    VK.lOption: "Left ⌥", VK.rOption: "Right ⌥", VK.lCommand: "Left ⌘", VK.rCommand: "Right ⌘",
  ]

  public static func name(_ vk: UInt32) -> String {
    switch vk {
    case 0x41...0x5A, 0x30...0x39: return String(UnicodeScalar(UInt8(vk)))
    case 0x70...0x83: return "F\(vk - 0x6F)"
    case 0x60...0x69: return "Num\(vk - 0x60)"
    default: return special[vk] ?? "Key \(String(vk, radix: 16, uppercase: true))"
    }
  }

  public static func display(_ h: Hotkey) -> String {
    guard h.vk != 0 else { return "—" }
    var s = ""
    if h.mods.contains(.control) { s += "⌃" }
    if h.mods.contains(.option) { s += "⌥" }
    if h.mods.contains(.shift) { s += "⇧" }
    if h.mods.contains(.command) { s += "⌘" }
    return s + name(h.vk)
  }

  /// A menu item key equivalent for letters and digits; nil for other keys.
  public static func menuKeyEquivalent(_ vk: UInt32) -> String? {
    switch vk {
    case 0x41...0x5A, 0x30...0x39: return name(vk).lowercased()
    default: return nil
    }
  }
}
