public enum MouseButton: Equatable, Sendable { case none, left, right, middle, x1, x2 }

public struct InputEvent: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case mouseDown, mouseUp, mouseMove, keyDown, keyUp }
  public var kind: Kind
  public var button: MouseButton
  public var vk: UInt32
  public var x: Int
  public var y: Int
  public var timeMs: UInt64
  public init(kind: Kind, button: MouseButton = .none, vk: UInt32 = 0, x: Int = 0, y: Int = 0, timeMs: UInt64 = 0) {
    self.kind = kind; self.button = button; self.vk = vk; self.x = x; self.y = y; self.timeMs = timeMs
  }
}

public struct Mods: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let control = Mods(rawValue: 1)
  public static let option = Mods(rawValue: 2)
  public static let shift = Mods(rawValue: 4)
  public static let command = Mods(rawValue: 8)
}

public struct Hotkey: Codable, Equatable, Sendable {
  public var mods: Mods
  public var vk: UInt32
  public init(mods: Mods, vk: UInt32) { self.mods = mods; self.vk = vk }
  /// ⌃⌥P
  public static let defaultToggle = Hotkey(mods: [.control, .option], vk: 0x50)
}

/// What starts a gesture: a held modifier or key plus a left press, or a side mouse button on its own.
public enum Trigger: Equatable, Sendable, Codable {
  case option, control, shift, command, mouse4, mouse5
  case key(UInt32)

  public init(from decoder: Decoder) throws {
    let s = try decoder.singleValueContainer().decode(String.self)
    switch s {
    case "option": self = .option
    case "control": self = .control
    case "shift": self = .shift
    case "command": self = .command
    case "mouse4": self = .mouse4
    case "mouse5": self = .mouse5
    default:
      guard s.hasPrefix("key:"), let vk = UInt32(s.dropFirst(4)), vk > 0, vk < 256 else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad trigger \(s)"))
      }
      self = .key(vk)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .option: try c.encode("option")
    case .control: try c.encode("control")
    case .shift: try c.encode("shift")
    case .command: try c.encode("command")
    case .mouse4: try c.encode("mouse4")
    case .mouse5: try c.encode("mouse5")
    case .key(let vk): try c.encode("key:\(vk)")
    }
  }
}

public struct GestureConfig: Equatable, Sendable {
  public var trigger: Trigger = .option
  public var clickPing = false
  /// Fullscreen apps (games) keep every click.
  public var gameCheck = false
  public var dragThresholdPx = 8
  public var toggle = Hotkey.defaultToggle
  public var enabled = true
  public init() {}
}

public struct GesturePoint: Equatable, Sendable {
  public var x: Int
  public var y: Int
  public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public enum GestureEmit: Equatable, Sendable {
  case wheelOpen(GesturePoint), wheelMove(GesturePoint), wheelRelease(GesturePoint), click(GesturePoint)
  case cancel
  case toggled(Bool)
}

/// A press the machine swallowed and now gives back to the system.
public enum Replay: Equatable, Sendable { case buttonDown(MouseButton), buttonUp(MouseButton) }

public struct GestureOutput: Equatable, Sendable {
  public var swallow = false
  public var emits: [GestureEmit] = []
  public var replays: [Replay] = []
  public init() {}
}
