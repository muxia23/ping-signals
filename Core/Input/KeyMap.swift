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
