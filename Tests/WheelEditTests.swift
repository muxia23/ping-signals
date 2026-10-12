import Testing
@testable import PingCore

@Suite struct WheelEditTests {
  let wheel = PingCatalog.defaultModernWheel  // danger push omw allin assist needvision missing enemyvision

  @Test func newPingReplacesSlot() {
    let w = WheelEdit.assign(.bait, toSlot: 1, in: wheel)
    #expect(w[1] == .bait && w.count == 8 && Set(w).count == 8)
  }

  @Test func existingPingSwaps() {
    let w = WheelEdit.assign(.missing, toSlot: 0, in: wheel)
    #expect(w[0] == .missing && w[6] == .danger)
  }

  @Test func sameSlotIsNoOp() {
    #expect(WheelEdit.assign(.danger, toSlot: 0, in: wheel) == wheel)
  }

  @Test func outOfRangeIsNoOp() {
    #expect(WheelEdit.assign(.bait, toSlot: 8, in: wheel) == wheel)
  }
}
