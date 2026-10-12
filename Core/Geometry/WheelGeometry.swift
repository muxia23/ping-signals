import Foundation

public enum WheelGeometry {
  /// The slice under an offset from the wheel centre, in screen coordinates (y down).
  /// nil inside the dead zone, else 0..<slots where 0 = north and indices go clockwise.
  /// Slices are 360/slots degrees wide and centred on their direction.
  public static func pickSlice(dx: Double, dy: Double, slots: Int, deadZone: Double) -> Int? {
    if (dx * dx + dy * dy).squareRoot() < deadZone { return nil }
    let span = 360.0 / Double(slots)
    let deg = (atan2(dy, dx) * 180 / .pi + 90 + span / 2 + 360).truncatingRemainder(dividingBy: 360)
    return Int(deg / span) % slots
  }
}
