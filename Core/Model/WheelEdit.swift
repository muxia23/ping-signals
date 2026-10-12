/// Editing the modern wheel's eight slots, which always hold eight different pings.
public enum WheelEdit {
  /// Puts `id` into `slot`; if `id` already sits in another slot, the two slots swap.
  public static func assign(_ id: PingID, toSlot slot: Int, in wheel: [PingID]) -> [PingID] {
    guard wheel.indices.contains(slot) else { return wheel }
    var w = wheel
    if let other = w.firstIndex(of: id) { w.swapAt(other, slot) } else { w[slot] = id }
    return w
  }
}
