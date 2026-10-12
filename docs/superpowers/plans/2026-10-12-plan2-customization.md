# Plan 2: Customization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every ping can be bound to a user-chosen action, and the app gets its settings window, onboarding, launch at login, pause-hotkey recording and zh/en UI.

**Architecture:** Pure logic (action config + lenient decoding, action context, key names, wheel slot editing) lives in PingCore with Swift Testing tests. App gets an `ActionRunner` that executes any `ActionConfig`, a SwiftUI settings window driven by an `@Observable SettingsModel`, and `AppCoordinator.apply(_:)` as the single place settings changes take effect.

**Tech Stack:** Swift 6, SwiftUI + AppKit, macOS 14, XcodeGen, Swift Testing, ServiceManagement.

**Spec:** `docs/superpowers/specs/2026-10-12-customization-design.md`

**Commands** (run from repo root):
- Test: `xcodegen generate >/dev/null && xcodebuild test -project PingSignals.xcodeproj -scheme PingSignals -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|Test run|SUCCEEDED|FAILED"` (never `-quiet`)
- Build: `xcodegen generate >/dev/null && xcodebuild build -project PingSignals.xcodeproj -scheme PingSignals -configuration Debug -derivedDataPath build -quiet 2>&1 | grep -E "error:|warning: .*Sendable" ; echo built`
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

### Task 1: ActionConfig and per-ping bindings in Settings

**Files:**
- Modify: `Core/Actions/PingActions.swift` (replace whole file)
- Modify: `Core/Model/Settings.swift`
- Modify: `Core/Model/PingCatalog.swift` (add `CodingKeyRepresentable` to `PingID`)
- Modify: `Tests/PingActionsTests.swift` (replace whole file)
- Modify: `Tests/SettingsTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Replace `Tests/PingActionsTests.swift`:

```swift
import Foundation
import Testing
@testable import PingCore

@Suite struct PingActionsTests {
  private func signal(_ id: PingID, _ source: PingSignal.Source = .wheel) -> PingSignal {
    PingSignal(ping: id, style: .classic, point: GesturePoint(0, 0), frontApp: nil, time: Date(), source: source)
  }

  @Test func defaultsMatchV2() {
    let d = PingActions.defaults
    #expect(d[.assist] == .claudeQuickEntry)
    #expect(d[.omw] == .todoPanel)
    #expect(d[.danger] == .retreat)
    #expect(d.count == PingID.allCases.count)
    for id in PingID.allCases where ![.assist, .omw, .danger].contains(id) { #expect(d[id] == ActionConfig.none, "\(id)") }
  }

  @Test func previewsNeverAct() {
    let a = PingActions.defaults
    #expect(PingActions.shouldAct(on: signal(.danger, .wheel), actions: a) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.danger, .click), actions: a) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.danger, .preview), actions: a) == nil)
  }

  @Test func ineffectiveActionsDoNothing() {
    var a = PingActions.defaults
    a[.missing] = .shell("   ")
    a[.push] = .keystroke(Hotkey(mods: [], vk: 0))
    a[.bait] = .open("")
    #expect(PingActions.shouldAct(on: signal(.missing), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.push), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.bait), actions: a) == nil)
    #expect(PingActions.shouldAct(on: signal(.generic), actions: a) == nil)
    a[.missing] = .shell("say hi")
    #expect(PingActions.shouldAct(on: signal(.missing), actions: a) == .shell("say hi"))
  }

  @Test func codableRoundTrip() throws {
    let all: [ActionConfig] = [.none, .retreat, .todoPanel, .claudeQuickEntry, .shortcut("翻译"),
                               .keystroke(Hotkey(mods: [.command, .shift], vk: 0x41)), .open("https://x.y"), .shell("ls")]
    for c in all {
      let back = try JSONDecoder().decode(ActionConfig.self, from: JSONEncoder().encode(c))
      #expect(back == c)
    }
    let json = String(decoding: try JSONEncoder().encode(ActionConfig.shortcut("A")), as: UTF8.self)
    #expect(json.contains(#""type":"shortcut""#) && json.contains(#""value":"A""#))
  }

  @Test func blankPerKind() {
    for k in ActionConfig.Kind.allCases { #expect(ActionConfig.blank(k).kind == k) }
  }
}
```

Add to `Tests/SettingsTests.swift` before `storePersists`:

```swift
  @Test func actionsDefaultAndRoundTrip() throws {
    #expect(Settings().actions == PingActions.defaults)
    var s = Settings()
    s.actions[.missing] = .shell("echo $PING_ID")
    s.actions[.danger] = ActionConfig.none
    #expect(Settings.decodeLeniently(try JSONEncoder().encode(s)) == s)
  }

  @Test func badActionEntriesFallBackIndividually() {
    let s = decode(#"{"actions": {"missing": {"type": "shell", "value": "ls"}, "danger": {"type": "laser"}, "omw": 3, "nope": {"type": "none"}}}"#)
    #expect(s.actions[.missing] == .shell("ls"))
    #expect(s.actions[.danger] == .retreat)      // unknown type → default
    #expect(s.actions[.omw] == .todoPanel)       // malformed → default
    #expect(s.actions[.assist] == .claudeQuickEntry)  // missing → default
    #expect(s.actions.count == PingID.allCases.count)
  }
```

- [ ] **Step 2: Run tests, expect compile failure** (`ActionConfig` undefined).

- [ ] **Step 3: Implement**

Replace `Core/Actions/PingActions.swift`:

```swift
import Foundation

/// What placing a ping does beyond its animation and sound. User-configurable per ping.
public enum ActionConfig: Equatable, Sendable, Codable {
  case none, retreat, todoPanel, claudeQuickEntry
  /// Runs a Shortcuts.app shortcut by name.
  case shortcut(String)
  /// Presses a key combination; modifiers may be empty (e.g. F13).
  case keystroke(Hotkey)
  /// A web address, any `scheme://` link, or a file URL of an app.
  case open(String)
  /// One shell command line, run with `zsh -lc`.
  case shell(String)

  public enum Kind: String, CaseIterable, Sendable, Identifiable {
    case none, retreat, todoPanel, claudeQuickEntry, shortcut, keystroke, open, shell
    public var id: String { rawValue }
  }

  public var kind: Kind {
    switch self {
    case .none: .none
    case .retreat: .retreat
    case .todoPanel: .todoPanel
    case .claudeQuickEntry: .claudeQuickEntry
    case .shortcut: .shortcut
    case .keystroke: .keystroke
    case .open: .open
    case .shell: .shell
    }
  }

  /// The action of `kind` with an empty parameter, used when the user switches kinds.
  public static func blank(_ kind: Kind) -> ActionConfig {
    switch kind {
    case .none: .none
    case .retreat: .retreat
    case .todoPanel: .todoPanel
    case .claudeQuickEntry: .claudeQuickEntry
    case .shortcut: .shortcut("")
    case .keystroke: .keystroke(Hotkey(mods: [], vk: 0))
    case .open: .open("")
    case .shell: .shell("")
    }
  }

  /// False for `.none` and for actions whose parameter is still blank.
  public var isEffective: Bool {
    func filled(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    switch self {
    case .none: return false
    case .retreat, .todoPanel, .claudeQuickEntry: return true
    case .shortcut(let s), .open(let s), .shell(let s): return filled(s)
    case .keystroke(let h): return KeyMap.vkToKeyCode(h.vk) != nil
    }
  }

  private enum Keys: String, CodingKey { case type, value }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch Kind(rawValue: type) {
    case .none?: self = .none
    case .retreat?: self = .retreat
    case .todoPanel?: self = .todoPanel
    case .claudeQuickEntry?: self = .claudeQuickEntry
    case .shortcut?: self = .shortcut(try c.decode(String.self, forKey: .value))
    case .keystroke?: self = .keystroke(try c.decode(Hotkey.self, forKey: .value))
    case .open?: self = .open(try c.decode(String.self, forKey: .value))
    case .shell?: self = .shell(try c.decode(String.self, forKey: .value))
    case nil: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown action \(type)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(kind.rawValue, forKey: .type)
    switch self {
    case .none, .retreat, .todoPanel, .claudeQuickEntry: break
    case .shortcut(let s), .open(let s), .shell(let s): try c.encode(s, forKey: .value)
    case .keystroke(let h): try c.encode(h, forKey: .value)
    }
  }
}

public enum PingActions {
  /// v2's fixed table: Danger retreats, On My Way opens the todo panel, Assist Me calls Claude.
  public static let defaults: [PingID: ActionConfig] = Dictionary(uniqueKeysWithValues: PingID.allCases.map { id in
    switch id {
    case .danger: (id, .retreat)
    case .omw: (id, .todoPanel)
    case .assist: (id, .claudeQuickEntry)
    default: (id, .none)
    }
  })

  /// The action to run for a placed ping, or nil (menu-bar previews never act).
  public static func shouldAct(on signal: PingSignal, actions: [PingID: ActionConfig]) -> ActionConfig? {
    guard signal.source != .preview, let c = actions[signal.ping], c.isEffective else { return nil }
    return c
  }

  /// Entry by entry: unknown pings and malformed entries are skipped; missing pings keep their default.
  public static func decodeLeniently(_ value: Any?) -> [PingID: ActionConfig] {
    var out = defaults
    guard let obj = value as? [String: Any] else { return out }
    for (key, v) in obj {
      guard let id = PingID(rawValue: key), JSONSerialization.isValidJSONObject([v]),
            let d = try? JSONSerialization.data(withJSONObject: [v]),
            let c = (try? JSONDecoder().decode([ActionConfig].self, from: d))?.first else { continue }
      out[id] = c
    }
    return out
  }
}
```

In `Core/Model/PingCatalog.swift`, change the `PingID` declaration line to:

```swift
public enum PingID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
```

In `Core/Model/Settings.swift`, add after `public var autoUpdateCheck = true`:

```swift
  /// What each ping does; every PingID has an entry.
  public var actions: [PingID: ActionConfig] = PingActions.defaults
```

and in `decodeLeniently`, before the `// A custom trigger key` comment:

```swift
    s.actions = PingActions.decodeLeniently(obj["actions"])
```

Update `App/Actions/PingAction.swift` so the app still builds (the runner arrives in Task 5): replace the `ActionRouter` class with

```swift
/// Signal handler that runs the action bound to each ping.
@MainActor
final class ActionRouter: SignalHandler {
  private let actions: [ActionConfig.Kind: PingAction]
  private let bindings: () -> [PingID: ActionConfig]

  init(actions: [ActionConfig.Kind: PingAction], bindings: @escaping () -> [PingID: ActionConfig]) {
    self.actions = actions
    self.bindings = bindings
  }

  func handle(_ signal: PingSignal) {
    guard let c = PingActions.shouldAct(on: signal, actions: bindings()) else { return }
    actions[c.kind]?.perform(signal)
  }
}
```

and in `App/AppCoordinator.swift` replace the `bus.register(ActionRouter(...))` call with

```swift
    bus.register(ActionRouter(actions: [
      .claudeQuickEntry: ClaudeQuickEntryAction(),
      .todoPanel: TodoPanelAction(panel: todoPanel),
      .retreat: RetreatAction(),
    ]) { [weak self] in self?.settings.actions ?? PingActions.defaults })
```

- [ ] **Step 4: Run tests** — expect all pass (previous count + 6).
- [ ] **Step 5: Commit** `git add -A Core Tests App && git commit -m "Per-ping action bindings in settings (ActionConfig)"`

---

### Task 2: ActionContext (environment variables and shortcut input)

**Files:**
- Create: `Core/Actions/ActionContext.swift`
- Create: `Tests/ActionContextTests.swift`

- [ ] **Step 1: Failing test** `Tests/ActionContextTests.swift`:

```swift
import Foundation
import Testing
@testable import PingCore

@Suite struct ActionContextTests {
  private let signal = PingSignal(ping: .missing, style: .modern, point: GesturePoint(-108, -540),
                                  frontApp: "com.apple.Safari", time: Date(), source: .wheel)

  @Test func environmentHasEveryKnownField() {
    let front = TodoContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Docs", url: "https://a.b")
    let env = ActionContext(signal: signal, front: front).environment
    #expect(env == ["PING_ID": "missing", "PING_STYLE": "modern", "PING_X": "-108", "PING_Y": "-540",
                    "FRONT_APP": "Safari", "FRONT_BUNDLE_ID": "com.apple.Safari", "WINDOW_TITLE": "Docs",
                    "FRONT_URL": "https://a.b"])
  }

  @Test func missingFieldsAreLeftOut() throws {
    let ctx = ActionContext(signal: signal, front: TodoContext(appName: "Finder"))
    #expect(ctx.environment["FRONT_URL"] == nil && ctx.environment["WINDOW_TITLE"] == nil)
    let obj = try JSONSerialization.jsonObject(with: ctx.jsonData()) as! [String: Any]
    #expect(obj["ping"] as? String == "missing")
    #expect(obj["x"] as? Int == -108)
    #expect(obj["app"] as? String == "Finder")
    #expect(obj["url"] == nil)
  }
}
```

- [ ] **Step 2: Run, expect failure** (`ActionContext` undefined).

- [ ] **Step 3: Implement** `Core/Actions/ActionContext.swift`:

```swift
import Foundation

/// What a shortcut or shell action is told about the ping: as environment variables or as JSON input.
public struct ActionContext: Equatable, Sendable {
  public let signal: PingSignal
  public let front: TodoContext

  public init(signal: PingSignal, front: TodoContext) {
    self.signal = signal
    self.front = front
  }

  private var fields: [(env: String, json: String, value: Any?)] {
    [("PING_ID", "ping", signal.ping.rawValue), ("PING_STYLE", "style", signal.style.rawValue),
     ("PING_X", "x", signal.point.x), ("PING_Y", "y", signal.point.y),
     ("FRONT_APP", "app", front.appName), ("FRONT_BUNDLE_ID", "bundleID", front.bundleID),
     ("WINDOW_TITLE", "windowTitle", front.windowTitle), ("FRONT_URL", "url", front.url)]
  }

  /// Variables added to a shell action's environment; absent values are not set.
  public var environment: [String: String] {
    var env: [String: String] = [:]
    for f in fields { if let v = f.value { env[f.env] = "\(v)" } }
    return env
  }

  /// Input for a shortcut: a JSON object, absent values left out.
  public func jsonData() -> Data {
    var obj: [String: Any] = [:]
    for f in fields { if let v = f.value { obj[f.json] = v } }
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
  }
}
```

- [ ] **Step 4: Run tests, expect pass.** (Run `xcodegen generate` first: new files.)
- [ ] **Step 5: Commit** `git add Core/Actions/ActionContext.swift Tests/ActionContextTests.swift && git commit -m "ActionContext: ping context as env vars and JSON"`

---

### Task 3: KeyNames and WheelEdit

**Files:**
- Create: `Core/Input/KeyNames.swift`, `Core/Model/WheelEdit.swift`
- Create: `Tests/KeyNamesTests.swift`, `Tests/WheelEditTests.swift`

- [ ] **Step 1: Failing tests**

`Tests/KeyNamesTests.swift`:

```swift
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
```

`Tests/WheelEditTests.swift`:

```swift
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
```

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: Implement**

`Core/Input/KeyNames.swift`:

```swift
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
```

`Core/Model/WheelEdit.swift`:

```swift
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
```

- [ ] **Step 4: `xcodegen generate`, run tests, expect pass.**
- [ ] **Step 5: Commit** `git add -A Core Tests && git commit -m "KeyNames and WheelEdit"`

---

### Task 4: ActionRunner (all action kinds)

**Files:**
- Create: `App/Actions/ActionRunner.swift`
- Modify: `App/Actions/PingAction.swift` (router uses the runner)
- Modify: `App/Todo/ContextCapture.swift` (add `captureWaitingForURL`)
- Modify: `App/Input/SyntheticInput.swift` (add `press(_:)`)
- Modify: `App/AppCoordinator.swift` (wiring)

- [ ] **Step 1: ContextCapture** — append inside `enum ContextCapture`:

```swift
  /// Like `capture`, but waits (at most `timeout`) for the browser URL so one-shot actions get it too.
  static func captureWaitingForURL(timeout: Duration = .seconds(1)) async -> TodoContext {
    let once = Once()
    return await withCheckedContinuation { (cont: CheckedContinuation<TodoContext, Never>) in
      var ctx = TodoContext()
      ctx = capture { url in
        guard !once.fired else { return }
        once.fired = true
        var withURL = once.base
        withURL.url = url
        cont.resume(returning: withURL)
      }
      once.base = ctx
      guard let id = ctx.bundleID, urlScript(for: id) != nil else {
        once.fired = true
        cont.resume(returning: ctx)
        return
      }
      Task { @MainActor in
        try? await Task.sleep(for: timeout)
        guard !once.fired else { return }
        once.fired = true
        cont.resume(returning: once.base)
      }
    }
  }

  @MainActor private final class Once {
    var fired = false
    var base = TodoContext()
  }
```

- [ ] **Step 2: SyntheticInput** — append inside `enum SyntheticInput`:

```swift
  /// Presses and releases `hotkey` (call after `whenModifiersReleased`).
  static func press(_ hotkey: Hotkey) {
    guard let code = KeyMap.vkToKeyCode(hotkey.vk) else { return }
    var flags: UInt64 = 0
    if hotkey.mods.contains(.control) { flags |= KeyMap.Flag.control }
    if hotkey.mods.contains(.option) { flags |= KeyMap.Flag.option }
    if hotkey.mods.contains(.shift) { flags |= KeyMap.Flag.shift }
    if hotkey.mods.contains(.command) { flags |= KeyMap.Flag.command }
    for down in [true, false] {
      guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
      e.flags = CGEventFlags(rawValue: flags)
      e.setIntegerValueField(.eventSourceUserData, value: marker)
      e.post(tap: .cghidEventTap)
    }
  }
```

- [ ] **Step 3: Create** `App/Actions/ActionRunner.swift`:

```swift
import AppKit
import PingCore

/// Runs any ActionConfig. Built-in actions keep their own classes; the generic ones live here.
/// Failures are logged only: an action must never get in the way of the ping itself.
@MainActor
final class ActionRunner {
  private let builtIn: [ActionConfig.Kind: PingAction]

  init(retreat: PingAction, todoPanel: PingAction, claude: PingAction) {
    builtIn = [.retreat: retreat, .todoPanel: todoPanel, .claudeQuickEntry: claude]
  }

  func run(_ config: ActionConfig, signal: PingSignal) {
    guard config.isEffective else { return }
    switch config {
    case .none: return
    case .retreat, .todoPanel, .claudeQuickEntry:
      builtIn[config.kind]?.perform(signal)
    case .keystroke(let h):
      SyntheticInput.whenModifiersReleased { SyntheticInput.press(h) }
    case .open(let s):
      let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let url = URL(string: trimmed), url.scheme != nil else {
        NSLog("ping-signals: not a URL: %@", trimmed)
        return
      }
      NSWorkspace.shared.open(url)
    case .shortcut(let name):
      withContext(signal) { ctx in Self.runShortcut(name, input: ctx.jsonData()) }
    case .shell(let command):
      withContext(signal) { ctx in Self.runShell(command, extraEnv: ctx.environment) }
    }
  }

  private func withContext(_ signal: PingSignal, _ body: @escaping @MainActor (ActionContext) -> Void) {
    Task { @MainActor in
      let front = await ContextCapture.captureWaitingForURL()
      body(ActionContext(signal: signal, front: front))
    }
  }

  private static func runShortcut(_ name: String, input: Data) {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("ping-\(UUID().uuidString).json")
    do { try input.write(to: file) } catch {
      NSLog("ping-signals: shortcut input not written: %@", "\(error)")
      return
    }
    launch("/usr/bin/shortcuts", ["run", name, "--input-path", file.path], env: nil, label: "shortcut \(name)") {
      try? FileManager.default.removeItem(at: file)
    }
  }

  private static func runShell(_ command: String, extraEnv: [String: String]) {
    let env = ProcessInfo.processInfo.environment.merging(extraEnv) { _, new in new }
    launch("/bin/zsh", ["-lc", command], env: env, label: "shell") {}
  }

  /// Starts a background process; never waits for it.
  private static func launch(_ path: String, _ args: [String], env: [String: String]?, label: String,
                             done: @escaping @Sendable () -> Void) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let env { p.environment = env }
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    p.terminationHandler = { proc in
      if proc.terminationStatus != 0 { NSLog("ping-signals: %@ exited with %d", label, proc.terminationStatus) }
      done()
    }
    do { try p.run() } catch {
      NSLog("ping-signals: %@ failed to start: %@", label, "\(error)")
      done()
    }
  }

  /// Names of the user's shortcuts (`shortcuts list`), for the settings picker.
  nonisolated static func listShortcuts() async -> [String] {
    await Task.detached {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
      p.arguments = ["list"]
      let out = Pipe()
      p.standardOutput = out
      p.standardError = FileHandle.nullDevice
      do { try p.run() } catch { return [] }
      let data = out.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }.value
  }
}
```

- [ ] **Step 4: Router** — replace `ActionRouter` in `App/Actions/PingAction.swift` with:

```swift
/// Signal handler that runs the action bound to each ping.
@MainActor
final class ActionRouter: SignalHandler {
  private let runner: ActionRunner
  private let bindings: () -> [PingID: ActionConfig]

  init(runner: ActionRunner, bindings: @escaping () -> [PingID: ActionConfig]) {
    self.runner = runner
    self.bindings = bindings
  }

  func handle(_ signal: PingSignal) {
    guard let c = PingActions.shouldAct(on: signal, actions: bindings()) else { return }
    runner.run(c, signal: signal)
  }
}
```

- [ ] **Step 5: Coordinator** — add a property `private var runner: ActionRunner!` and replace the router registration with:

```swift
    runner = ActionRunner(retreat: RetreatAction(), todoPanel: TodoPanelAction(panel: todoPanel),
                          claude: ClaudeQuickEntryAction())
    bus.register(ActionRouter(runner: runner) { [weak self] in self?.settings.actions ?? PingActions.defaults })
```

- [ ] **Step 6: Build and run tests**, expect success.
- [ ] **Step 7: Manual smoke test** — temporarily nothing to configure in UI yet; instead write settings by hand:
  ```bash
  defaults read com.muxia.ping-signals settings.v1 2>/dev/null | head -1
  ```
  (Verified fully in Task 8 via the Actions tab.)
- [ ] **Step 8: Commit** `git add -A App && git commit -m "ActionRunner: shortcuts, keystrokes, open, shell"`

---

### Task 5: AppCoordinator.apply, launch at login, menu

**Files:**
- Create: `App/Settings/LaunchAtLogin.swift`
- Modify: `App/AppCoordinator.swift`, `App/MenuBarController.swift`

- [ ] **Step 1: Create** `App/Settings/LaunchAtLogin.swift`:

```swift
import ServiceManagement

@MainActor
enum LaunchAtLogin {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      NSLog("ping-signals: launch at login %@ failed: %@", on ? "register" : "unregister", "\(error)")
    }
  }
}
```

- [ ] **Step 2: Coordinator** — add (in `// MARK: Menu actions` area) and change `setStyle` to use it:

```swift
  /// The one place a settings change takes effect.
  func apply(_ new: Settings) {
    let old = settings
    guard new != old else { return }
    settings = new
    store.save(new)
    // Re-sending the config also cancels any gesture in progress (needed when the wheel changes).
    tap.apply(machine.setConfig(new.gestureConfig(enabled: machine.enabled)))
    overlay.cancelWheel()
    if new.style != old.style || new.wheel != old.wheel { refreshWheelArt() }
    if new.launchAtLogin != old.launchAtLogin { LaunchAtLogin.set(new.launchAtLogin) }
    onSettingsChanged?(new)
    refreshMenu()
  }

  /// Lets the settings window follow changes made elsewhere (e.g. the menu's style switch).
  var onSettingsChanged: ((Settings) -> Void)?

  private func setStyle(_ s: WheelStyle) {
    var new = settings
    new.style = s
    apply(new)
  }
```

(Delete the old `setStyle` body.)

- [ ] **Step 3: Menu** — `MenuBarController.Actions` gains `var openSettings: () -> Void`; `update` gains a `toggleHotkey: Hotkey` parameter. Replace the toggle item block with:

```swift
    let toggle = entry(enabled ? "暂停 / Pause" : "启用 / Enable") { [actions] in actions.toggleEnabled() }
    if let key = KeyNames.menuKeyEquivalent(toggleHotkey.vk) {
      toggle.keyEquivalent = key
      var mask: NSEvent.ModifierFlags = []
      if toggleHotkey.mods.contains(.control) { mask.insert(.control) }
      if toggleHotkey.mods.contains(.option) { mask.insert(.option) }
      if toggleHotkey.mods.contains(.shift) { mask.insert(.shift) }
      if toggleHotkey.mods.contains(.command) { mask.insert(.command) }
      toggle.keyEquivalentModifierMask = mask
    }
    menu.addItem(toggle)
```

and before the Quit separator add:

```swift
    menu.addItem(.separator())
    let settingsItem = entry("设置… / Settings…") { [actions] in actions.openSettings() }
    settingsItem.keyEquivalent = ","
    menu.addItem(settingsItem)
```

Coordinator: pass `openSettings: { [weak self] in self?.openSettings() }` (stub `private func openSettings() {}` until Task 6) and `refreshMenu()` passes `toggleHotkey: settings.toggleHotkey`.

- [ ] **Step 4: Build, run tests.** Manually: switch style from menu → wheel changes, still works.
- [ ] **Step 5: Commit** `git add -A App && git commit -m "AppCoordinator.apply as the single settings entry point; menu shows the pause hotkey"`

---

### Task 6: Settings window shell, Trigger / Pings & Sound / General tabs, key recorder

**Files:**
- Create: `App/Settings/SettingsModel.swift`, `App/Settings/SettingsWindowController.swift`, `App/Settings/SettingsView.swift`, `App/Settings/KeyRecorder.swift`, `App/Settings/GeneralTabs.swift`, `App/Settings/Names.swift`
- Modify: `App/AppCoordinator.swift`

- [ ] **Step 1: Names** `App/Settings/Names.swift` (UI strings; English keys, localized in Task 10):

```swift
import Foundation
import PingCore

enum Names {
  static func ping(_ id: PingID) -> String {
    switch id {
    case .danger: String(localized: "Danger")
    case .push: String(localized: "Push")
    case .omw: String(localized: "On My Way")
    case .allin: String(localized: "All In")
    case .assist: String(localized: "Assist Me")
    case .needvision: String(localized: "Need Vision")
    case .missing: String(localized: "Enemy Missing")
    case .enemyvision: String(localized: "Enemy Vision")
    case .generic: String(localized: "Ping")
    case .bait: String(localized: "Bait")
    case .visioncleared: String(localized: "Vision Cleared")
    }
  }

  static func action(_ k: ActionConfig.Kind) -> String {
    switch k {
    case .none: String(localized: "Nothing")
    case .retreat: String(localized: "Retreat")
    case .todoPanel: String(localized: "Todo Panel")
    case .claudeQuickEntry: String(localized: "Call Claude")
    case .shortcut: String(localized: "Run Shortcut")
    case .keystroke: String(localized: "Press Keys")
    case .open: String(localized: "Open App or URL")
    case .shell: String(localized: "Run Shell Command")
    }
  }
}

```

- [ ] **Step 2: Model** `App/Settings/SettingsModel.swift`:

```swift
import AppKit
import Observation
import PingCore

/// The settings window's state. Edits go straight to the coordinator.
@MainActor @Observable
final class SettingsModel {
  var settings: Settings {
    didSet { if settings != oldValue { apply(settings) } }
  }
  var shortcuts: [String] = []
  /// Language the app is running in, to tell whether a restart is pending.
  let launchLanguage: LanguagePref

  @ObservationIgnored private let apply: (Settings) -> Void
  @ObservationIgnored let tryAction: (ActionConfig, PingID) -> Void
  @ObservationIgnored let setRecording: (Bool) -> Void

  init(settings: Settings, apply: @escaping (Settings) -> Void,
       tryAction: @escaping (ActionConfig, PingID) -> Void, setRecording: @escaping (Bool) -> Void) {
    self.settings = settings
    self.launchLanguage = settings.language
    self.apply = apply
    self.tryAction = tryAction
    self.setRecording = setRecording
  }

  func refreshShortcuts() {
    Task { shortcuts = await ActionRunner.listShortcuts() }
  }

  func restart() {
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}
```

- [ ] **Step 3: Key recorder** `App/Settings/KeyRecorder.swift`:

```swift
import AppKit
import PingCore
import SwiftUI

/// Click, then press a key (combination). Esc cancels. `validate` returns an error message or nil.
struct KeyRecorder: View {
  @Binding var value: Hotkey
  var validate: (Hotkey) -> String? = { _ in nil }
  let setRecording: (Bool) -> Void

  @State private var recording = false
  @State private var monitor: Any?
  @State private var error: String?

  var body: some View {
    HStack(spacing: 8) {
      Button(recording ? String(localized: "Press keys…") : KeyNames.display(value)) {
        recording ? stop() : start()
      }
      .frame(minWidth: 90)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onDisappear { stop() }
  }

  private func start() {
    error = nil
    recording = true
    setRecording(true)
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
      let f = e.modifierFlags
      if e.keyCode == 0x35 && f.intersection([.control, .option, .shift, .command]).isEmpty {  // Esc
        stop()
        return nil
      }
      let vk = KeyMap.keyCodeToVK(e.keyCode)
      guard vk != 0 else { return nil }
      var mods: Mods = []
      if f.contains(.control) { mods.insert(.control) }
      if f.contains(.option) { mods.insert(.option) }
      if f.contains(.shift) { mods.insert(.shift) }
      if f.contains(.command) { mods.insert(.command) }
      let h = Hotkey(mods: mods, vk: vk)
      if let msg = validate(h) { error = msg; return nil }
      value = h
      stop()
      return nil
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if recording { setRecording(false) }
    recording = false
  }
}
```

- [ ] **Step 4: Tabs** `App/Settings/GeneralTabs.swift`:

```swift
import PingCore
import SwiftUI

struct TriggerTab: View {
  @Bindable var model: SettingsModel

  private enum Choice: Hashable { case option, control, shift, command, mouse4, mouse5, custom }

  private var choice: Binding<Choice> {
    Binding {
      switch model.settings.trigger {
      case .option: .option
      case .control: .control
      case .shift: .shift
      case .command: .command
      case .mouse4: .mouse4
      case .mouse5: .mouse5
      case .key: .custom
      }
    } set: { c in
      let t: Trigger = switch c {
      case .option: .option
      case .control: .control
      case .shift: .shift
      case .command: .command
      case .mouse4: .mouse4
      case .mouse5: .mouse5
      case .custom: .key(model.settings.toggleHotkey.vk == 0xC0 ? 0x7C : 0xC0)  // ` (or F13)
      }
      if t != model.settings.trigger { model.settings.trigger = t }
    }
  }

  private var customKey: Binding<Hotkey> {
    Binding {
      if case .key(let vk) = model.settings.trigger { return Hotkey(mods: [], vk: vk) }
      return Hotkey(mods: [], vk: 0)
    } set: { model.settings.trigger = .key($0.vk) }
  }

  var body: some View {
    Form {
      Picker("Trigger key", selection: choice) {
        Text("⌥ Option").tag(Choice.option)
        Text("⌃ Control").tag(Choice.control)
        Text("⇧ Shift").tag(Choice.shift)
        Text("⌘ Command").tag(Choice.command)
        Text("Mouse button 4").tag(Choice.mouse4)
        Text("Mouse button 5").tag(Choice.mouse5)
        Text("Custom key…").tag(Choice.custom)
      }
      if case .key = model.settings.trigger {
        LabeledContent("Custom key") {
          KeyRecorder(value: customKey, validate: { h in
            h.vk == model.settings.toggleHotkey.vk ? String(localized: "Used by the pause shortcut") : nil
          }, setRecording: model.setRecording)
        }
      }
      LabeledContent("Drag distance") {
        HStack {
          Slider(value: Binding { Double(model.settings.dragThresholdPx) } set: { model.settings.dragThresholdPx = Int($0) },
                 in: Double(Settings.dragRange.lowerBound)...Double(Settings.dragRange.upperBound), step: 1)
          Text("\(model.settings.dragThresholdPx) px").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
      }
      Toggle("Trigger key + click places a ping", isOn: $model.settings.clickPing)
      Toggle("Let clicks through in full-screen games", isOn: $model.settings.gameCheck)
    }
    .formStyle(.grouped)
  }
}

struct PingsSoundTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      LabeledContent("Ping size") {
        HStack {
          Slider(value: Binding { Double(model.settings.pingSizePx) } set: { model.settings.pingSizePx = Int($0) },
                 in: Double(Settings.sizeRange.lowerBound)...Double(Settings.sizeRange.upperBound), step: 5)
          Text("\(model.settings.pingSizePx) px").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      LabeledContent("Ping duration") {
        HStack {
          Slider(value: $model.settings.pingDurationS, in: Settings.durationRange, step: 0.1)
          Text(String(format: "%.1f s", model.settings.pingDurationS)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      LabeledContent("Volume") {
        HStack {
          Slider(value: Binding { Double(model.settings.volume) } set: { model.settings.volume = Int($0) }, in: 0...100, step: 1)
          Text("\(model.settings.volume)%").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
      }
      Toggle("Mute", isOn: $model.settings.muted)
      Toggle("Tick sound when moving over the wheel", isOn: $model.settings.tickSound)
    }
    .formStyle(.grouped)
  }
}

struct GeneralTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      LabeledContent("Pause shortcut") {
        KeyRecorder(value: $model.settings.toggleHotkey, validate: { h in
          if h.mods.isDisjoint(with: [.control, .option, .command]) { return String(localized: "Include ⌃, ⌥ or ⌘") }
          if case .key(let vk) = model.settings.trigger, vk == h.vk { return String(localized: "Used by the trigger key") }
          return nil
        }, setRecording: model.setRecording)
      }
      Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
      Picker("Language", selection: $model.settings.language) {
        Text("Automatic").tag(LanguagePref.auto)
        Text(verbatim: "简体中文").tag(LanguagePref.zhHans)
        Text(verbatim: "English").tag(LanguagePref.en)
      }
      if model.settings.language != model.launchLanguage {
        HStack {
          Text("Takes effect after a restart").foregroundStyle(.secondary)
          Spacer()
          Button("Restart Now") { model.restart() }
        }
      }
      LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
    }
    .formStyle(.grouped)
  }
}
```

- [ ] **Step 5: Window** `App/Settings/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
  @Bindable var model: SettingsModel

  var body: some View {
    TabView {
      TriggerTab(model: model).tabItem { Label("Trigger", systemImage: "cursorarrow.click.2") }
      Text("").tabItem { Label("Wheel", systemImage: "circle.grid.cross") }        // Task 7
      PingsSoundTab(model: model).tabItem { Label("Pings & Sound", systemImage: "speaker.wave.2") }
      Text("").tabItem { Label("Actions", systemImage: "bolt") }                   // Task 8
      GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
    }
    .frame(width: 620, height: 560)
  }
}
```

`App/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
  let model: SettingsModel
  private var window: NSWindow?

  init(model: SettingsModel) { self.model = model }

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
      w.title = String(localized: "ping-signals Settings")
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    model.settings.launchAtLogin = LaunchAtLogin.isEnabled   // the user may have changed it in System Settings
    model.refreshShortcuts()
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }
}
```

- [ ] **Step 6: Coordinator** — add:

```swift
  private lazy var settingsWindow: SettingsWindowController = {
    let model = SettingsModel(settings: settings,
      apply: { [weak self] in self?.apply($0) },
      tryAction: { [weak self] c, id in self?.tryAction(c, id) },
      setRecording: { [weak self] on in self?.setRecording(on) })
    onSettingsChanged = { [weak model] s in model?.settings = s }
    return SettingsWindowController(model: model)
  }()

  private func openSettings() { settingsWindow.show() }

  /// Key recording must see the keys the gesture machine would otherwise act on (e.g. the pause shortcut).
  private func setRecording(_ on: Bool) { tap.apply(machine.setSuspended(on)) }

  private func tryAction(_ c: ActionConfig, _ id: PingID) {
    runner.run(c, signal: PingSignal(ping: id, style: settings.style, point: overlay.mouseScreenCenter(),
                                     frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                     time: Date(), source: .preview))
  }
```

- [ ] **Step 7: `xcodegen generate`, build, run tests.** Manual: open Settings from the menu; change trigger to ⌃ → ⌃+drag opens the wheel; record a pause shortcut ⌃⌥K → menu shows it, ⌃⌥K pauses; drag distance, size, volume take effect immediately.
- [ ] **Step 8: Commit** `git add -A App && git commit -m "Settings window: trigger, pings & sound, general tabs; key recorder"`

---

### Task 7: Wheel tab

**Files:**
- Create: `App/Settings/WheelTab.swift`
- Modify: `App/Settings/SettingsView.swift` (use `WheelTab`)

- [ ] **Step 1: Create** `App/Settings/WheelTab.swift`:

```swift
import PingCore
import SwiftUI

struct WheelTab: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(spacing: 16) {
      Picker("Style", selection: $model.settings.style) {
        Text("Classic (2022)").tag(WheelStyle.classic)
        Text("Modern").tag(WheelStyle.modern)
      }
      .pickerStyle(.segmented)
      .frame(width: 300)

      if model.settings.style == .classic { classic } else { modern }
      Spacer()
    }
    .padding(20)
  }

  /// Classic slots are fixed: up, right, down, left.
  private var classic: some View {
    VStack(spacing: 10) {
      Text("↑ " + Names.ping(.danger))
      HStack(spacing: 40) {
        Text("← " + Names.ping(.missing))
        Text("⌥ + click: \(Names.ping(.generic))").foregroundStyle(.secondary)
        Text(Names.ping(.omw) + " →")
      }
      Text("↓ " + Names.ping(.assist))
      Text("The classic wheel is fixed.").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
    }
    .font(.title3)
  }

  private var modern: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle().strokeBorder(.quaternary, lineWidth: 1).frame(width: 300, height: 300)
        ForEach(0..<8, id: \.self) { slot in
          let a = Double(slot) * .pi / 4
          slotPicker(slot).offset(x: sin(a) * 150, y: -cos(a) * 150)
        }
        Picker("", selection: $model.settings.clickPingID) {
          ForEach(PingID.allCases, id: \.self) { Text(Names.ping($0)).tag($0) }
        }
        .labelsHidden().frame(width: 130)
        .help("Placed by trigger key + click")
      }
      .frame(width: 440, height: 360)
      Text("Choosing a ping that's already on the wheel swaps the two slots. The centre is the trigger-key + click ping.")
        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(width: 440)
      Button("Restore Defaults") {
        model.settings.wheel = PingCatalog.defaultModernWheel
        model.settings.clickPingID = .generic
      }
    }
  }

  private func slotPicker(_ slot: Int) -> some View {
    Picker("", selection: Binding {
      model.settings.wheel[slot]
    } set: { id in
      model.settings.wheel = WheelEdit.assign(id, toSlot: slot, in: model.settings.wheel)
    }) {
      ForEach(PingID.allCases.filter { $0 != .generic }, id: \.self) { Text(Names.ping($0)).tag($0) }
    }
    .labelsHidden()
    .frame(width: 130)
  }
}
```

- [ ] **Step 2:** In `SettingsView`, replace the Wheel placeholder with `WheelTab(model: model).tabItem { Label("Wheel", systemImage: "circle.grid.cross") }`.
- [ ] **Step 3: Build.** Manual: switch to modern, set slot 0 to Bait → wheel shows Bait at the top; set slot 1 to Bait → slots 0/1 swap; Restore Defaults works; style switch here and in the menu stay in sync.
- [ ] **Step 4: Commit** `git add -A App && git commit -m "Settings: wheel tab with slot pickers"`

---

### Task 8: Actions tab

**Files:**
- Create: `App/Settings/ActionsTab.swift`
- Modify: `App/Settings/SettingsView.swift`

- [ ] **Step 1: Create** `App/Settings/ActionsTab.swift`:

```swift
import AppKit
import PingCore
import SwiftUI

struct ActionsTab: View {
  @Bindable var model: SettingsModel
  @State private var showModern = false

  private static let main: [PingID] = [.danger, .omw, .assist, .missing, .generic]
  private static let modernOnly: [PingID] = [.push, .allin, .needvision, .enemyvision, .bait, .visioncleared]

  var body: some View {
    Form {
      Section {
        ForEach(Self.main, id: \.self) { ActionRow(id: $0, model: model) }
      } footer: {
        Text("Shortcuts and shell commands receive the ping and the front app, window and URL (PING_ID, FRONT_APP, FRONT_URL…).")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section {
        DisclosureGroup("Modern wheel only", isExpanded: $showModern) {
          ForEach(Self.modernOnly, id: \.self) { ActionRow(id: $0, model: model) }
        }
      }
      HStack {
        Spacer()
        Button("Restore Defaults") { model.settings.actions = PingActions.defaults }
      }
    }
    .formStyle(.grouped)
  }
}

private struct ActionRow: View {
  let id: PingID
  @Bindable var model: SettingsModel

  private var config: Binding<ActionConfig> {
    Binding { model.settings.actions[id] ?? .none } set: { model.settings.actions[id] = $0 }
  }

  private var kind: Binding<ActionConfig.Kind> {
    Binding { config.wrappedValue.kind } set: { k in
      if k != config.wrappedValue.kind { config.wrappedValue = .blank(k) }
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(Names.ping(id)).frame(width: 100, alignment: .leading)
      Picker("", selection: kind) {
        ForEach(ActionConfig.Kind.allCases) { Text(Names.action($0)).tag($0) }
      }
      .labelsHidden().frame(width: 160)
      parameter.frame(maxWidth: .infinity, alignment: .leading)
      Button("Try") { model.tryAction(config.wrappedValue, id) }
        .disabled(!config.wrappedValue.isEffective)
    }
  }

  @ViewBuilder private var parameter: some View {
    switch config.wrappedValue {
    case .shortcut(let name):
      HStack(spacing: 4) {
        Picker("", selection: Binding { name } set: { config.wrappedValue = .shortcut($0) }) {
          Text("Choose…").tag("")
          ForEach(model.shortcuts.contains(name) || name.isEmpty ? model.shortcuts : [name] + model.shortcuts,
                  id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        Button { model.refreshShortcuts() } label: { Image(systemName: "arrow.clockwise") }
          .buttonStyle(.borderless).help("Reload shortcuts")
      }
    case .keystroke(let h):
      KeyRecorder(value: Binding { h } set: { config.wrappedValue = .keystroke($0) }, setRecording: model.setRecording)
    case .open(let s):
      HStack(spacing: 4) {
        TextField("https://… or app", text: Binding { s } set: { config.wrappedValue = .open($0) })
          .labelsHidden()
        Button("App…") { chooseApp() }
      }
    case .shell(let cmd):
      TextField("command", text: Binding { cmd } set: { config.wrappedValue = .shell($0) })
        .labelsHidden().font(.system(.body, design: .monospaced))
    default:
      EmptyView()
    }
  }

  private func chooseApp() {
    let panel = NSOpenPanel()
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowedContentTypes = [.application]
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url { config.wrappedValue = .open(url.absoluteString) }
  }
}
```

- [ ] **Step 2:** In `SettingsView`, replace the Actions placeholder with `ActionsTab(model: model).tabItem { Label("Actions", systemImage: "bolt") }`.
- [ ] **Step 3: Build.** Manual, each with a real ping and with Try:
  1. Enemy Missing → Run Shell Command `say $PING_ID` → hear "missing".
  2. Enemy Missing → Run Shell Command `echo "$FRONT_APP $FRONT_URL" >> /tmp/ping.log` in Safari → log has app and URL.
  3. A shortcut that shows its input (Shortcuts: "Show Result" of Shortcut Input) → JSON appears.
  4. Press Keys ⌘⇧4 → screenshot crosshair.
  5. Open App or URL → `https://github.com` and App… → Calculator.
  6. Nothing; Restore Defaults restores Danger/On My Way/Assist Me.
- [ ] **Step 4: Commit** `git add -A App && git commit -m "Settings: actions tab"`

---

### Task 9: Onboarding window

**Files:**
- Create: `App/Settings/OnboardingWindowController.swift`
- Modify: `App/AccessibilityGate.swift`, `App/AppCoordinator.swift`, `App/MenuBarController.swift`

- [ ] **Step 1: Create** `App/Settings/OnboardingWindowController.swift`:

```swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
  private var window: NSWindow?

  func show() {
    if window == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView()))
      w.title = "ping-signals"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      window = w
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  func close() { window?.close() }
}

private struct OnboardingView: View {
  var body: some View {
    VStack(spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
      Text("Allow ping-signals to see ⌥ + drag").font(.title2.bold())
      Text("ping-signals needs Accessibility access to notice the trigger key and the mouse. It doesn't read what you type and sends nothing anywhere.")
        .multilineTextAlignment(.center).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 6) {
        Text("1. Click “Open System Settings”.")
        Text("2. Turn on ping-signals under Accessibility.")
        Text("3. Come back: this window closes by itself.")
      }
      Button("Open System Settings") { AccessibilityGate.requestAndOpenSettings() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(28)
    .frame(width: 440)
  }
}
```

- [ ] **Step 2: Gate** — in `AccessibilityGate`, remove the `prompt` parameter and its system-prompt block (`waitForPermission(onGranted:)` only polls), update the doc comment, and add:

```swift
  /// Puts the app into the Accessibility list (the system prompt) and opens the pane.
  static func requestAndOpenSettings() {
    let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary  // literal kAXTrustedCheckOptionPrompt
    _ = AXIsProcessTrustedWithOptions(opts)
    openSettings()
  }
```

- [ ] **Step 3: Coordinator** — add `private let onboarding = OnboardingWindowController()`; change `armTap(prompt:)` to:

```swift
  /// `showGuide`: open the onboarding window while waiting (not when permission was revoked later:
  /// the menu's "Grant Accessibility…" item opens it then).
  private func armTap(showGuide: Bool) {
    if showGuide && !gate.isTrusted { onboarding.show() }
    gate.waitForPermission { [weak self] in
      self?.onboarding.close()
      self?.startTap()
    }
  }
```

Update callers: `armTap(prompt: true)` → `armTap(showGuide: true)`, others → `armTap(showGuide: false)`. In `MenuBarController`, the "Grant Accessibility…" item calls a new `actions.showOnboarding` (coordinator passes `{ [weak self] in self?.onboarding.show() }`) instead of `AccessibilityGate.openSettings()`.

- [ ] **Step 4: Build, tests.** Manual: `tccutil reset Accessibility com.muxia.ping-signals`, relaunch → onboarding shows; grant → window closes, wheel works.
- [ ] **Step 5: Commit** `git add -A App && git commit -m "Onboarding window replaces the system permission prompt"`

---

### Task 10: zh-Hans / en localization and language override

**Files:**
- Create: `App/Resources/en.lproj/Localizable.strings`, `App/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `App/MenuBarController.swift` (English keys via `String(localized:)`), `App/main.swift` (language override), `project.yml` (`options.developmentLanguage: en`)

- [ ] **Step 1: Menu strings** — replace each bilingual literal: `"需要「辅助功能」权限… / Grant Accessibility…"` → `String(localized: "Grant Accessibility…")`, `"暂停 / Pause"` → `String(localized: "Pause")`, `"启用 / Enable"` → `String(localized: "Enable")`, `"经典（2022）/ Classic"` → `String(localized: "Classic (2022)")`, `"新版 / Modern"` → `String(localized: "Modern")`, `"轮盘风格 / Wheel Style"` → `String(localized: "Wheel Style")`, `"预览标记 / Preview Ping"` → `String(localized: "Preview Ping")`, preview entries `id.rawValue` → `Names.ping(id)`, `"设置… / Settings…"` → `String(localized: "Settings…")`, `"退出 / Quit"` → `String(localized: "Quit")`.

- [ ] **Step 2: Language override** — in `App/main.swift`, before `let app = NSApplication.shared`:

```swift
// Language preference applies from launch (AppKit reads AppleLanguages once).
switch SettingsStore().load().language {
case .auto: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
case .zhHans: UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
case .en: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
}
```

- [ ] **Step 3: Strings files.** Collect every key: `grep -rhoE 'String\(localized: "[^"]+"\)|(Text|Button|Toggle|Picker|Label|LabeledContent|Section|DisclosureGroup|TextField)\("[^"]+"' App | sort -u`. Write `en.lproj/Localizable.strings` with each key mapping to itself and `zh-Hans.lproj/Localizable.strings` with translations, e.g.:

```
"Danger" = "危险";
"Push" = "推进";
"On My Way" = "正在路上";
"All In" = "全力进攻";
"Assist Me" = "请求协助";
"Need Vision" = "需要视野";
"Enemy Missing" = "敌人消失";
"Enemy Vision" = "敌方视野";
"Ping" = "标记";
"Bait" = "诱饵";
"Vision Cleared" = "视野已清除";
"Nothing" = "无";
"Retreat" = "撤退";
"Todo Panel" = "待办面板";
"Call Claude" = "呼叫 Claude";
"Run Shortcut" = "运行快捷指令";
"Press Keys" = "按快捷键";
"Open App or URL" = "打开应用或网址";
"Run Shell Command" = "运行 Shell 命令";
"Pause" = "暂停";
"Enable" = "启用";
"Settings…" = "设置…";
"Quit" = "退出";
```

(and every other collected key; interpolated keys such as `"%lld px"` / `"⌥ + click: %@"` use the format-specifier form). In `project.yml` add under `options:` the line `developmentLanguage: en`.

- [ ] **Step 4: Build.** Manual: Settings → General → Language 简体中文 → Restart Now → menu and settings in Chinese; English → English; Automatic follows the system.
- [ ] **Step 5: Commit** `git add -A App project.yml && git commit -m "zh-Hans / en localization; language override"`

---

### Task 11: Previews, user confirmation, docs

**Files:**
- Modify: `App/main.swift` (`--render-settings <dir>`)
- Modify: `README.md`, `README_EN.md`, `CLAUDE.md` (index, untracked), spec status

- [ ] **Step 1: Preview renderer** — in `App/main.swift`, after the `--render-wheels` block:

```swift
// `ping-signals --render-settings <dir>` writes each settings tab and the onboarding window as PNGs.
if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
  let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  _ = NSApplication.shared
  MainActor.assumeIsolated { SettingsPreview.render(to: dir) }
  exit(0)
}
```

and create `App/Settings/SettingsPreview.swift` that, for each tab view (`TriggerTab`, `WheelTab` classic and modern, `PingsSoundTab`, `ActionsTab` with the modern group expanded, `GeneralTab`) and the onboarding view, puts an `NSHostingView` of size 620×560 into an offscreen borderless `NSWindow`, calls `layoutSubtreeIfNeeded()`, and writes `bitmapImageRepForCachingDisplay` / `cacheDisplay` to `<dir>/<name>.png`. The model uses `Settings()` with a sample `.shell("say $PING_ID")` on Enemy Missing and no-op closures. (Make `OnboardingView` internal for this.)

- [ ] **Step 2:** Render to the scratchpad, view every PNG, fix anything clipped or misaligned.
- [ ] **Step 3: STOP — show the previews to the user and wait for confirmation** before restarting the running app (memory rule: visual changes need a preview first).
- [ ] **Step 4:** After confirmation, restart the app and run the manual checks of Tasks 6–10.
- [ ] **Step 5: Docs** — README roadmap: tick settings window / onboarding / launch at login / zh-en; add a "Custom actions" section (the 7 kinds + env-var table from the spec) in both READMEs; add settings screenshots (`docs/images/settings-actions.png`). Update `CLAUDE.md` structure (`App/Settings/`) and `WORKLOG.md`.
- [ ] **Step 6: Commit** `git add -A && git commit -m "Settings previews; README: custom actions"`; ask the user before merging to `main` and pushing.
