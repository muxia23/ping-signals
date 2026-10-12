import Testing
@testable import PingCore

@Suite struct KeyMapTests {
  @Test func vkConstants() {
    #expect(VK.lOption == 0xA4)
    #expect(VK.lControl == 0xA2)
    #expect(VK.escape == 0x1B)
  }

  @Test func keyCodesMapToVKs() {
    #expect(KeyMap.keyCodeToVK(0x23) == 0x50)      // P
    #expect(KeyMap.keyCodeToVK(0x00) == 0x41)      // A
    #expect(KeyMap.keyCodeToVK(0x1D) == 0x30)      // 0
    #expect(KeyMap.keyCodeToVK(0x35) == VK.escape)
    #expect(KeyMap.keyCodeToVK(0x7A) == 0x70)      // F1
    #expect(KeyMap.keyCodeToVK(0x5A) == 0x83)      // F20
    #expect(KeyMap.keyCodeToVK(0x7B) == 0x25)      // left arrow
    #expect(KeyMap.keyCodeToVK(0x3F) == 0)         // fn has no VK
    #expect(KeyMap.vkToKeyCode(0x50) == 0x23)
    #expect(KeyMap.vkToKeyCode(VK.enter) == 0x24)  // Return, not keypad Enter
    #expect(KeyMap.vkToKeyCode(VK.lOption) == 0x3A)
    #expect(KeyMap.vkToKeyCode(0x87) == nil)       // F24 doesn't exist on a Mac
    for code in UInt16(0)..<0x80 {
      let vk = KeyMap.keyCodeToVK(code)
      if vk != 0 && code != 0x4C { #expect(KeyMap.vkToKeyCode(vk) == code) }  // keypad Enter shares Return's VK
    }
  }

  @Test func modifierHeld() {
    typealias F = KeyMap.Flag
    #expect(KeyMap.modifierHeld(F.option | F.devLAlt, VK.lOption))
    #expect(!KeyMap.modifierHeld(F.option | F.devLAlt, VK.rOption))
    #expect(KeyMap.modifierHeld(F.option | F.devRAlt, VK.rOption))
    #expect(KeyMap.modifierHeld(F.option, VK.lOption))        // synthetic event without side bits: left
    #expect(!KeyMap.modifierHeld(F.option, VK.rOption))
    #expect(!KeyMap.modifierHeld(F.devLAlt, VK.lOption))      // stale side bit with the group up
    #expect(KeyMap.modifierHeld(F.command | F.devRCmd, VK.rCommand))
    #expect(KeyMap.modifierHeld(F.control | F.devRCtrl, VK.rControl))
    #expect(!KeyMap.modifierHeld(F.shift | F.devLShift, 0x41))
  }

  @Test func modifierTransitions() {
    typealias F = KeyMap.Flag
    var t = KeyMap.modifierTransitions(from: 0, to: F.option | F.devLAlt)
    #expect(t == [KeyTransition(vk: VK.lOption, down: true)])
    t = KeyMap.modifierTransitions(from: F.option | F.devLAlt, to: 0)
    #expect(t == [KeyTransition(vk: VK.lOption, down: false)])
    // Option released and Control pressed in one step: ups come first.
    t = KeyMap.modifierTransitions(from: F.option | F.devLAlt, to: F.control | F.devLCtrl)
    #expect(t == [KeyTransition(vk: VK.lOption, down: false), KeyTransition(vk: VK.lControl, down: true)])
    // Right Command added to left Command.
    t = KeyMap.modifierTransitions(from: F.command | F.devLCmd, to: F.command | F.devLCmd | F.devRCmd)
    #expect(t == [KeyTransition(vk: VK.rCommand, down: true)])
    #expect(KeyMap.modifierTransitions(from: F.shift | F.devLShift, to: F.shift | F.devLShift).isEmpty)
  }
}
