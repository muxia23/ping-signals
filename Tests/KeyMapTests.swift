import Testing
@testable import PingCore

@Suite struct KeyMapTests {
  @Test func vkConstants() {
    #expect(VK.lOption == 0xA4)
    #expect(VK.lControl == 0xA2)
    #expect(VK.escape == 0x1B)
  }
}
