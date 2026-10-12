import Foundation
import Testing
@testable import PingCore

@Suite struct WheelGeometryTests {
  // Offsets are in screen coordinates: y grows downward.
  @Test func eightSlicesCompass() {
    let r = 150.0
    let dirs: [(Double, Double)] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
    for (i, d) in dirs.enumerated() {
      let len = (d.0 * d.0 + d.1 * d.1).squareRoot()
      #expect(WheelGeometry.pickSlice(dx: d.0 / len * r, dy: d.1 / len * r, slots: 8, deadZone: 86) == i)
    }
  }

  @Test func eightSliceBoundaries() {
    // 22.4° clockwise from north is still north; 22.6° is north-east.
    let rad = { (deg: Double) in deg * .pi / 180 }
    #expect(WheelGeometry.pickSlice(dx: 150 * sin(rad(22.4)), dy: -150 * cos(rad(22.4)), slots: 8, deadZone: 86) == 0)
    #expect(WheelGeometry.pickSlice(dx: 150 * sin(rad(22.6)), dy: -150 * cos(rad(22.6)), slots: 8, deadZone: 86) == 1)
    #expect(WheelGeometry.pickSlice(dx: -150 * sin(rad(22.4)), dy: -150 * cos(rad(22.4)), slots: 8, deadZone: 86) == 0)
    #expect(WheelGeometry.pickSlice(dx: -150 * sin(rad(22.6)), dy: -150 * cos(rad(22.6)), slots: 8, deadZone: 86) == 7)
  }

  @Test func fourSlices() {
    #expect(WheelGeometry.pickSlice(dx: 0, dy: -100, slots: 4, deadZone: 50) == 0)   // N
    #expect(WheelGeometry.pickSlice(dx: 100, dy: 0, slots: 4, deadZone: 50) == 1)    // E
    #expect(WheelGeometry.pickSlice(dx: 0, dy: 100, slots: 4, deadZone: 50) == 2)    // S
    #expect(WheelGeometry.pickSlice(dx: -100, dy: 0, slots: 4, deadZone: 50) == 3)   // W
    // Boundaries at ±45°.
    #expect(WheelGeometry.pickSlice(dx: 70, dy: -71, slots: 4, deadZone: 50) == 0)
    #expect(WheelGeometry.pickSlice(dx: 71, dy: -70, slots: 4, deadZone: 50) == 1)
  }

  @Test func deadZone() {
    #expect(WheelGeometry.pickSlice(dx: 0, dy: 0, slots: 8, deadZone: 86) == nil)
    #expect(WheelGeometry.pickSlice(dx: 85, dy: 0, slots: 8, deadZone: 86) == nil)
    #expect(WheelGeometry.pickSlice(dx: 86, dy: 0, slots: 8, deadZone: 86) == 2)
  }
}
