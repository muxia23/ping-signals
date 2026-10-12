import Testing
@testable import PingCore

@Suite struct KeyNamesTests {
  @Test func names() {
    #expect(KeyNames.name(0x50) == "P")
    #expect(KeyNames.name(0x37) == "7")
    #expect(KeyNames.name(0x70) == "F1")
    #expect(KeyNames.name(0x83) == "F20")
    #expect(KeyNames.name(0x20) == "Space")
    #expect(KeyNames.name(0x0D) == "↩")
    #expect(KeyNames.name(0x26) == "↑")
    #expect(KeyNames.name(0xC0) == "`")
    #expect(KeyNames.name(0x65) == "Num5")
    #expect(KeyNames.name(0xE7) == "Key E7")
  }

  @Test func hotkeyDisplayUsesMacModifierOrder() {
    #expect(KeyNames.display(.defaultToggle) == "⌃⌥P")
    #expect(KeyNames.display(Hotkey(mods: [.command, .shift, .control, .option], vk: 0x41)) == "⌃⌥⇧⌘A")
    #expect(KeyNames.display(Hotkey(mods: [], vk: 0)) == "—")
  }

  @Test func menuKeyEquivalent() {
    #expect(KeyNames.menuKeyEquivalent(0x50) == "p")
    #expect(KeyNames.menuKeyEquivalent(0x31) == "1")
    #expect(KeyNames.menuKeyEquivalent(0x70) == nil)
  }
}
