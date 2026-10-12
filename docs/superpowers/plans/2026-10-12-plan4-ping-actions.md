# ping-signals Plan 4：标记动作 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 请求协助 → 打开 Claude 快速输入框；正在路上 → 右侧滑出待办面板（自动附带应用 / 窗口标题 / 网址，可跳回）；危险 → 撤退（隐藏全部窗口）/ 再打恢复。问号与普通标记无动作。

**Architecture:** 在 Plan 1 的 `SignalBus` 上新增一个 `ActionRouter`（`SignalHandler`），按 `PingActions.kind(for:)` 查表分发给三个 `PingAction`。纯逻辑（动作对照表、撤退状态机、待办存储）放 `PingCore` 并单元测试；系统交互（模拟按键、窗口隐藏、上下文采集、面板 UI）放 App。

**Tech Stack:** Swift 6、AppKit、SwiftUI（面板内容）、Observation（`@Observable`）、ApplicationServices（AX、CGEvent）、`/usr/bin/osascript`（读浏览器网址）。

**设计文档：** `docs/superpowers/specs/2026-10-12-ping-actions-design.md`

**已验证：** 模拟双击 ⌥（两次 `flagsChanged`，左 Option，间隔约 90 ms，`post(tap: .cghidEventTap)`）能唤出 Claude 桌面版快速输入框（2026-10-12 用独立小程序实测：出现 layer 1000 的全屏 Claude 窗口）。Claude bundle id：`com.anthropic.claudefordesktop`。已安装浏览器：Safari `com.apple.Safari`、Chrome `com.google.Chrome`、Arc `company.thebrowser.Browser`。

---

## 文件结构

```
Core/
├── Actions/PingActions.swift      PingActionKind + PingActions.kind / shouldAct
├── Actions/RetreatState.swift     RunningApp / RetreatPlan / RetreatState
├── Todo/TodoStore.swift           TodoContext / TodoItem / TodoStore（@Observable，JSON 持久化）
└── Signals/SignalBus.swift        （改）PingSignal.Source 增加 .preview
App/
├── Actions/PingAction.swift       PingAction 协议 + ActionRouter
├── Actions/ClaudeQuickEntryAction.swift
├── Actions/RetreatAction.swift
├── Actions/TodoPanelAction.swift
├── Input/SyntheticInput.swift     自标记常量、等修饰键松开、模拟双击 ⌥
├── Input/EventTap.swift           （改）自标记改用 SyntheticInput.marker
├── Todo/ContextCapture.swift      前台应用、窗口标题、浏览器网址
├── Todo/TodoPanelController.swift 右侧滑出的 NSPanel
├── Todo/TodoPanelView.swift       SwiftUI 面板内容
└── AppCoordinator.swift           （改）注册 ActionRouter；预览用 .preview
Tests/
├── PingActionsTests.swift
├── RetreatStateTests.swift
└── TodoStoreTests.swift
project.yml                        （改）NSAppleEventsUsageDescription
```

命令同 Plan 1（在 `~/sandbox/ping-signals` 下）：
- 跑测试：`xcodegen generate >/dev/null && xcodebuild test -project PingSignals.xcodeproj -scheme PingSignals -destination 'platform=macOS,arch=arm64' -derivedDataPath build 2>&1 | grep -E "error:|passed|failed|SUCCEEDED|FAILED" | tail -40`
- 编译应用：`xcodegen generate >/dev/null && xcodebuild build -project PingSignals.xcodeproj -scheme PingSignals -configuration Debug -derivedDataPath build -quiet 2>&1 | grep -E "error" | head`

**用户正在使用 Debug 版应用。** 编译不影响正在运行的实例；除 Task 8 外不要启动或结束应用。

---

### Task 1: 动作对照表与「预览」来源

预览菜单放出的标记只看动画，不能触发动作（否则预览「危险」会把所有窗口藏起来）。

**Files:**
- Create: `Core/Actions/PingActions.swift`, `Tests/PingActionsTests.swift`
- Modify: `Core/Signals/SignalBus.swift`（`Source` 枚举）, `App/AppCoordinator.swift`（`preview`）

- [ ] **Step 1: 写失败测试**

`Tests/PingActionsTests.swift`：

```swift
import Foundation
import Testing
@testable import PingCore

@Suite struct PingActionsTests {
  @Test func mapping() {
    #expect(PingActions.kind(for: .assist) == .claudeQuickEntry)
    #expect(PingActions.kind(for: .omw) == .todoPanel)
    #expect(PingActions.kind(for: .danger) == .retreat)
    for id in PingID.allCases where ![.assist, .omw, .danger].contains(id) {
      #expect(PingActions.kind(for: id) == nil, "\(id)")
    }
  }

  @Test func previewsNeverAct() {
    func signal(_ source: PingSignal.Source) -> PingSignal {
      PingSignal(ping: .danger, style: .classic, point: GesturePoint(0, 0), frontApp: nil, time: Date(), source: source)
    }
    #expect(PingActions.shouldAct(on: signal(.wheel)) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.click)) == .retreat)
    #expect(PingActions.shouldAct(on: signal(.preview)) == nil)
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译失败，`cannot find 'PingActions' in scope`（以及 `.preview` 不存在）。

- [ ] **Step 3: 实现**

`Core/Signals/SignalBus.swift` 中把

```swift
  public enum Source: Equatable, Sendable { case wheel, click }
```

改为

```swift
  /// `.preview`: placed from the menu bar to look at it; never triggers an action.
  public enum Source: Equatable, Sendable { case wheel, click, preview }
```

`Core/Actions/PingActions.swift`：

```swift
/// What placing a ping does beyond its animation and sound.
public enum PingActionKind: Equatable, Sendable {
  case claudeQuickEntry, todoPanel, retreat
}

public enum PingActions {
  /// The same in both styles. Pings without an entry only animate.
  public static func kind(for id: PingID) -> PingActionKind? {
    switch id {
    case .assist: return .claudeQuickEntry
    case .omw: return .todoPanel
    case .danger: return .retreat
    default: return nil
    }
  }

  public static func shouldAct(on signal: PingSignal) -> PingActionKind? {
    signal.source == .preview ? nil : kind(for: signal.ping)
  }
}
```

`App/AppCoordinator.swift` 的 `preview(_:)` 里把 `source: .click` 改为 `source: .preview`。

- [ ] **Step 4: 跑测试确认通过；编译应用**

Expected: 全部通过（原 67 + 2）；编译成功。

- [ ] **Step 5: Commit**

```bash
git add Core/Actions Core/Signals/SignalBus.swift App/AppCoordinator.swift Tests/PingActionsTests.swift
git commit -m "Add ping action table; menu previews never trigger actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 撤退状态机

**Files:**
- Create: `Core/Actions/RetreatState.swift`, `Tests/RetreatStateTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/RetreatStateTests.swift`：

```swift
import Testing
@testable import PingCore

@Suite struct RetreatStateTests {
  private func app(_ pid: Int32, regular: Bool = true, hidden: Bool = false, me: Bool = false) -> RunningApp {
    RunningApp(pid: pid, isRegular: regular, isHidden: hidden, isSelf: me)
  }

  @Test func retreatHidesVisibleRegularAppsButNotSelf() {
    var s = RetreatState()
    let plan = s.toggle(running: [app(1), app(2, hidden: true), app(3, regular: false), app(4, me: true), app(5)], frontmost: 5)
    #expect(plan == RetreatPlan(hide: [1, 5]))
    #expect(s.isRetreated)
  }

  @Test func restoreUnhidesAndActivatesFormerFront() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(5)], frontmost: 5)
    let plan = s.toggle(running: [app(1, hidden: true), app(5, hidden: true)], frontmost: nil)
    #expect(plan == RetreatPlan(unhide: [1, 5], activate: 5))
    #expect(!s.isRetreated)
  }

  @Test func restoreSkipsAppsThatQuit() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(2)], frontmost: 2)
    let plan = s.toggle(running: [app(1, hidden: true)], frontmost: nil)
    #expect(plan == RetreatPlan(unhide: [1], activate: nil))
  }

  @Test func frontmostNotHiddenIsNotReactivated() {
    var s = RetreatState()
    _ = s.toggle(running: [app(1), app(4, me: true)], frontmost: 4)   // our own app was in front
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan(unhide: [1], activate: nil))
  }

  @Test func cyclesRepeatedly() {
    var s = RetreatState()
    for _ in 0..<3 {
      #expect(s.toggle(running: [app(1)], frontmost: 1) == RetreatPlan(hide: [1]))
      #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan(unhide: [1], activate: 1))
    }
  }

  @Test func retreatWithNothingVisibleStillToggles() {
    var s = RetreatState()
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan())
    #expect(s.isRetreated)
    #expect(s.toggle(running: [app(1, hidden: true)], frontmost: nil) == RetreatPlan())
    #expect(!s.isRetreated)
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译失败，`cannot find 'RetreatState' in scope`。

- [ ] **Step 3: 实现**

`Core/Actions/RetreatState.swift`：

```swift
public struct RunningApp: Equatable, Sendable {
  public let pid: Int32
  /// Has a Dock icon and normal windows (NSApplication.ActivationPolicy.regular).
  public let isRegular: Bool
  public let isHidden: Bool
  public let isSelf: Bool
  public init(pid: Int32, isRegular: Bool, isHidden: Bool, isSelf: Bool) {
    self.pid = pid; self.isRegular = isRegular; self.isHidden = isHidden; self.isSelf = isSelf
  }
}

public struct RetreatPlan: Equatable, Sendable {
  public var hide: [Int32]
  public var unhide: [Int32]
  public var activate: Int32?
  public init(hide: [Int32] = [], unhide: [Int32] = [], activate: Int32? = nil) {
    self.hide = hide; self.unhide = unhide; self.activate = activate
  }
}

/// The Danger ping: the first press hides every visible app, the next one brings back exactly those.
public struct RetreatState: Sendable {
  public private(set) var isRetreated = false
  private var hidden: [Int32] = []
  private var front: Int32?

  public init() {}

  public mutating func toggle(running: [RunningApp], frontmost: Int32?) -> RetreatPlan {
    isRetreated ? restore(running: running) : retreat(running: running, frontmost: frontmost)
  }

  private mutating func retreat(running: [RunningApp], frontmost: Int32?) -> RetreatPlan {
    hidden = running.filter { $0.isRegular && !$0.isHidden && !$0.isSelf }.map(\.pid)
    front = frontmost.flatMap { hidden.contains($0) ? $0 : nil }
    isRetreated = true
    return RetreatPlan(hide: hidden)
  }

  private mutating func restore(running: [RunningApp]) -> RetreatPlan {
    let alive = Set(running.map(\.pid))
    let plan = RetreatPlan(unhide: hidden.filter { alive.contains($0) },
                           activate: front.flatMap { alive.contains($0) ? $0 : nil })
    hidden = []
    front = nil
    isRetreated = false
    return plan
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: Commit**

```bash
git add Core/Actions/RetreatState.swift Tests/RetreatStateTests.swift
git commit -m "Add retreat state machine for the Danger ping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 待办存储

**Files:**
- Create: `Core/Todo/TodoStore.swift`, `Tests/TodoStoreTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/TodoStoreTests.swift`（日期用整秒，因为 ISO 8601 存储不保留小数秒）：

```swift
import Foundation
import Testing
@testable import PingCore

@MainActor
@Suite struct TodoStoreTests {
  private let dir = FileManager.default.temporaryDirectory.appendingPathComponent("todo-tests-\(UUID().uuidString)")
  private var file: URL { dir.appendingPathComponent("todos.json") }
  private let ctx = TodoContext(appName: "Safari", bundleID: "com.apple.Safari", windowTitle: "Paper", url: "https://example.com/a")
  private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

  @Test func addTrimsAndRejectsEmpty() {
    let s = TodoStore(fileURL: file)
    #expect(s.add("   ", context: ctx, now: t(1)) == nil)
    let item = s.add("  read section 3  ", context: ctx, now: t(1))
    #expect(item?.text == "read section 3")
    #expect(item?.url == "https://example.com/a" && item?.windowTitle == "Paper" && item?.appName == "Safari")
    #expect(s.items.count == 1)
  }

  @Test func openNewestFirstAndDoneSeparately() {
    let s = TodoStore(fileURL: file)
    let a = s.add("a", context: ctx, now: t(1))!
    _ = s.add("b", context: ctx, now: t(2))
    let c = s.add("c", context: ctx, now: t(3))!
    s.toggleDone(a.id, now: t(10))
    s.toggleDone(c.id, now: t(11))
    #expect(s.open.map(\.text) == ["b"])
    #expect(s.done.map(\.text) == ["c", "a"])   // most recently finished first
    s.toggleDone(c.id, now: t(12))               // un-finish
    #expect(s.open.map(\.text) == ["c", "b"])
  }

  @Test func editAndDelete() {
    let s = TodoStore(fileURL: file)
    let a = s.add("a", context: ctx, now: t(1))!
    s.edit(a.id, text: "  A2 ")
    #expect(s.items.first?.text == "A2")
    s.edit(a.id, text: "   ")                    // empty edit is ignored
    #expect(s.items.first?.text == "A2")
    s.delete(a.id)
    #expect(s.items.isEmpty)
  }

  @Test func persistsAcrossInstances() {
    let s = TodoStore(fileURL: file)
    let a = s.add("keep me", context: ctx, now: t(100))!
    s.toggleDone(a.id, now: t(200))
    let back = TodoStore(fileURL: file)
    #expect(back.items == s.items)
    #expect(back.items.first?.doneAt == t(200))
  }

  @Test func badEntriesAreSkippedNotFatal() throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let json = """
    [{"id":"\(UUID().uuidString)","text":"good","createdAt":"1970-01-01T00:00:05Z"},
     {"text":"no id"},
     42]
    """
    try Data(json.utf8).write(to: file)
    let s = TodoStore(fileURL: file)
    #expect(s.items.map(\.text) == ["good"])
  }

  @Test func missingFileIsEmpty() {
    #expect(TodoStore(fileURL: file).items.isEmpty)
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Expected: 编译失败，`cannot find 'TodoStore' in scope`。

- [ ] **Step 3: 实现**

`Core/Todo/TodoStore.swift`：

```swift
import Foundation
import Observation

/// Where the user was when the On My Way ping fired.
public struct TodoContext: Equatable, Sendable {
  public var appName: String?
  public var bundleID: String?
  public var windowTitle: String?
  public var url: String?
  public init(appName: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, url: String? = nil) {
    self.appName = appName; self.bundleID = bundleID; self.windowTitle = windowTitle; self.url = url
  }
}

public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public var text: String
  public let createdAt: Date
  public var doneAt: Date?
  public var appName: String?
  public var bundleID: String?
  public var windowTitle: String?
  public var url: String?

  public var isDone: Bool { doneAt != nil }
}

/// The todo list behind the side panel, saved as JSON after every change.
@MainActor
@Observable
public final class TodoStore {
  public private(set) var items: [TodoItem] = []
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    items = Self.load(fileURL)
  }

  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ping-signals/todos.json")
  }

  /// Unfinished, newest first.
  public var open: [TodoItem] { items.filter { !$0.isDone }.sorted { $0.createdAt > $1.createdAt } }
  /// Finished, most recently finished first.
  public var done: [TodoItem] {
    items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
  }

  @discardableResult
  public func add(_ text: String, context: TodoContext, now: Date = Date()) -> TodoItem? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return nil }
    let item = TodoItem(id: UUID(), text: t, createdAt: now, doneAt: nil, appName: context.appName,
                        bundleID: context.bundleID, windowTitle: context.windowTitle, url: context.url)
    items.append(item)
    save()
    return item
  }

  public func toggleDone(_ id: UUID, now: Date = Date()) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].doneAt = items[i].doneAt == nil ? now : nil
    save()
  }

  public func edit(_ id: UUID, text: String) {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
    items[i].text = t
    save()
  }

  public func delete(_ id: UUID) {
    items.removeAll { $0.id == id }
    save()
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(items) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Decodes item by item: a broken entry is skipped, the rest survive.
  private static func load(_ url: URL) -> [TodoItem] {
    guard let data = try? Data(contentsOf: url),
          let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return array.compactMap { obj in
      guard JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
      return try? decoder.decode(TodoItem.self, from: d)
    }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: Commit**

```bash
git add Core/Todo Tests/TodoStoreTests.swift
git commit -m "Add todo store with lenient JSON persistence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 模拟按键与「请求协助 → Claude」

**Files:**
- Create: `App/Input/SyntheticInput.swift`, `App/Actions/PingAction.swift`, `App/Actions/ClaudeQuickEntryAction.swift`
- Modify: `App/Input/EventTap.swift`（删掉自己的 `selfMarker`，改用 `SyntheticInput.marker`）

- [ ] **Step 1: SyntheticInput**

`App/Input/SyntheticInput.swift`：

```swift
import AppKit
import PingCore

/// Keyboard events this app posts. They carry `marker`, so our own EventTap lets them through untouched.
@MainActor
enum SyntheticInput {
  /// "LPIN" in eventSourceUserData.
  static let marker: Int64 = 0x4C50_494E

  /// Runs `body` once no modifier key is physically held (at most 2 s later). A ping fires while ⌥ is
  /// still down from the gesture; synthetic modifier taps sent then would merge with the real key.
  static func whenModifiersReleased(_ body: @escaping @MainActor () async -> Void) {
    Task { @MainActor in
      let mods = KeyMap.Flag.shift | KeyMap.Flag.control | KeyMap.Flag.option | KeyMap.Flag.command
      var waited = 0
      while CGEventSource.flagsState(.hidSystemState).rawValue & mods != 0 && waited < 2000 {
        try? await Task.sleep(for: .milliseconds(30))
        waited += 30
      }
      await body()
    }
  }

  /// Two quick taps of the left Option key: Claude desktop's default Quick Entry shortcut.
  static func doubleTapOption() async {
    postOption(down: true)
    try? await Task.sleep(for: .milliseconds(40))
    postOption(down: false)
    try? await Task.sleep(for: .milliseconds(90))
    postOption(down: true)
    try? await Task.sleep(for: .milliseconds(40))
    postOption(down: false)
  }

  private static func postOption(down: Bool) {
    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0x3A, keyDown: down) else { return }  // kVK_Option
    e.type = .flagsChanged
    let nonCoalesced: UInt64 = 0x100
    e.flags = CGEventFlags(rawValue: down ? KeyMap.Flag.option | KeyMap.Flag.devLAlt | nonCoalesced : nonCoalesced)
    e.setIntegerValueField(.eventSourceUserData, value: marker)
    e.post(tap: .cghidEventTap)
  }
}
```

- [ ] **Step 2: EventTap 改用共享标记**

在 `App/Input/EventTap.swift` 中删除 `private static let selfMarker: Int64 = 0x4C50_494E`（及其上方注释），并把其余所有 `Self.selfMarker` 替换为 `SyntheticInput.marker`。
Run: `grep -n "selfMarker\|SyntheticInput.marker" App/Input/EventTap.swift` → Expected: 只剩 `SyntheticInput.marker`（2 处：过滤判断、post 时写入）。

- [ ] **Step 3: PingAction 协议与 ActionRouter**

`App/Actions/PingAction.swift`：

```swift
import PingCore

@MainActor
protocol PingAction: AnyObject {
  func perform(_ signal: PingSignal)
}

/// Signal handler that runs the action bound to each ping (see PingActions).
@MainActor
final class ActionRouter: SignalHandler {
  private let actions: [PingActionKind: PingAction]

  init(actions: [PingActionKind: PingAction]) { self.actions = actions }

  func handle(_ signal: PingSignal) {
    guard let kind = PingActions.shouldAct(on: signal) else { return }
    actions[kind]?.perform(signal)
  }
}
```

- [ ] **Step 4: ClaudeQuickEntryAction**

`App/Actions/ClaudeQuickEntryAction.swift`：

```swift
import AppKit
import PingCore

/// Assist Me: opens Claude desktop's Quick Entry by double-tapping ⌥ (launching Claude first if needed).
@MainActor
final class ClaudeQuickEntryAction: PingAction {
  static let bundleID = "com.anthropic.claudefordesktop"
  /// Time for a freshly launched Claude to register its shortcut.
  private static let launchWait: Duration = .seconds(3)

  func perform(_ signal: PingSignal) {
    let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    if !running {
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else {
        NSLog("ping-signals: Claude.app not found")
        return
      }
      let cfg = NSWorkspace.OpenConfiguration()
      cfg.activates = false
      NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }
    SyntheticInput.whenModifiersReleased {
      if !running { try? await Task.sleep(for: Self.launchWait) }
      await SyntheticInput.doubleTapOption()
    }
  }
}
```

- [ ] **Step 5: 编译应用、跑测试**

Expected: 编译成功；测试全绿（新增文件不影响测试数）。

- [ ] **Step 6: Commit**

```bash
git add App/Input/SyntheticInput.swift App/Input/EventTap.swift App/Actions/PingAction.swift App/Actions/ClaudeQuickEntryAction.swift
git commit -m "Assist Me opens Claude Quick Entry via a synthetic double ⌥

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 「危险 → 撤退」

**Files:**
- Create: `App/Actions/RetreatAction.swift`

- [ ] **Step 1: 实现**

`App/Actions/RetreatAction.swift`：

```swift
import AppKit
import PingCore

/// Danger: hide every visible app; the next Danger brings exactly those back.
@MainActor
final class RetreatAction: PingAction {
  private var state = RetreatState()

  func perform(_ signal: PingSignal) {
    let apps = NSWorkspace.shared.runningApplications
    let me = ProcessInfo.processInfo.processIdentifier
    let running = apps.map {
      RunningApp(pid: $0.processIdentifier, isRegular: $0.activationPolicy == .regular,
                 isHidden: $0.isHidden, isSelf: $0.processIdentifier == me)
    }
    let plan = state.toggle(running: running, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    var byPID: [Int32: NSRunningApplication] = [:]
    for a in apps { byPID[a.processIdentifier] = a }
    for pid in plan.hide { byPID[pid]?.hide() }
    for pid in plan.unhide { byPID[pid]?.unhide() }
    if let pid = plan.activate { byPID[pid]?.activate() }
  }
}
```

- [ ] **Step 2: 编译应用**

- [ ] **Step 3: Commit**

```bash
git add App/Actions/RetreatAction.swift
git commit -m "Danger retreats: hide all apps, next Danger restores them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 上下文采集（应用 / 窗口标题 / 网址）

**Files:**
- Create: `App/Todo/ContextCapture.swift`
- Modify: `project.yml`（`PingSignals.info.properties` 增加 `NSAppleEventsUsageDescription`）

- [ ] **Step 1: project.yml 加自动化权限说明**

在 `targets.PingSignals.info.properties` 下（与 `LSUIElement` 同级）追加：

```yaml
        NSAppleEventsUsageDescription: "ping-signals reads the current browser tab's address so a todo can take you back there."
```

- [ ] **Step 2: 实现**

`App/Todo/ContextCapture.swift`：

```swift
import AppKit
import PingCore

/// What the user was looking at when a ping fired. Must run before our own panel takes focus.
@MainActor
enum ContextCapture {
  /// App and window title now; the browser URL (if any) arrives later through `onURL`, because
  /// AppleScript can take a moment and asks for Automation permission the first time.
  static func capture(onURL: @escaping @MainActor (String) -> Void) -> TodoContext {
    guard let app = NSWorkspace.shared.frontmostApplication else { return TodoContext() }
    let ctx = TodoContext(appName: app.localizedName, bundleID: app.bundleIdentifier,
                          windowTitle: windowTitle(pid: app.processIdentifier), url: nil)
    if let id = app.bundleIdentifier, let script = urlScript(for: id) {
      Task.detached {
        if let url = runAppleScript(script) { await onURL(url) }
      }
    }
    return ctx
  }

  /// Title of the focused window via the Accessibility API (permission already granted for the event tap).
  private static func windowTitle(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, "AXFocusedWindow" as CFString, &window) == .success,
          let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
    var title: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, "AXTitle" as CFString, &title) == .success,
          let s = title as? String, !s.isEmpty else { return nil }
    return s
  }

  static func urlScript(for bundleID: String) -> String? {
    switch bundleID {
    case "com.apple.Safari":
      return #"tell application id "com.apple.Safari" to get URL of current tab of front window"#
    case "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser":
      return #"tell application id "\#(bundleID)" to get URL of active tab of front window"#
    default:
      return nil
    }
  }

  /// Runs osascript in a child process (thread-safe, unlike NSAppleScript off the main thread).
  nonisolated private static func runAppleScript(_ source: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", source]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    let s = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty || s == "missing value" ? nil : s
  }
}
```

- [ ] **Step 3: 编译应用、确认 Info.plist**

Run: 编译应用，然后 `/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" build/Build/Products/Debug/ping-signals.app/Contents/Info.plist`
Expected: 打印出上面的说明文字。

- [ ] **Step 4: Commit**

```bash
git add project.yml App/Todo/ContextCapture.swift
git commit -m "Capture front app, window title and browser URL for todos

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 侧边待办面板

**Files:**
- Create: `App/Todo/TodoPanelView.swift`, `App/Todo/TodoPanelController.swift`, `App/Actions/TodoPanelAction.swift`

- [ ] **Step 1: 面板内容（SwiftUI）**

`App/Todo/TodoPanelView.swift`：

```swift
import AppKit
import SwiftUI
import PingCore

/// The text being typed and the context it will be saved with.
@MainActor
@Observable
final class TodoDraft {
  var text = ""
  var context = TodoContext()
  /// Bumped every time the panel is summoned, to put the focus back in the text field.
  var focusToken = 0
}

struct TodoPanelView: View {
  @Bindable var draft: TodoDraft
  let store: TodoStore
  let onClose: () -> Void
  let onOpenSource: (TodoItem) -> Void

  @FocusState private var inputFocused: Bool
  @State private var showDone = false
  @State private var editing: UUID?
  @State private var editText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("待办").font(.headline)
        Spacer()
        Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
      }
      TextField("记点什么…（回车保存）", text: $draft.text)
        .textFieldStyle(.roundedBorder)
        .focused($inputFocused)
        .onSubmit {
          if store.add(draft.text, context: draft.context) != nil { draft.text = "" }
          inputFocused = true
        }
      if let source = Self.sourceLabel(appName: draft.context.appName, title: draft.context.windowTitle, url: draft.context.url) {
        Label(source, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(store.open) { row($0) }
          if !store.done.isEmpty {
            DisclosureGroup("已完成（\(store.done.count)）", isExpanded: $showDone) {
              ForEach(store.done) { row($0) }
            }
            .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(14)
    .frame(width: 360)
    .frame(maxHeight: .infinity, alignment: .top)
    .onAppear { inputFocused = true }
    .onChange(of: draft.focusToken) { inputFocused = true }
    .onExitCommand(perform: onClose)
  }

  @ViewBuilder
  private func row(_ item: TodoItem) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Button { store.toggleDone(item.id) } label: {
        Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
      }
      .buttonStyle(.plain)
      VStack(alignment: .leading, spacing: 2) {
        if editing == item.id {
          TextField("", text: $editText)
            .textFieldStyle(.roundedBorder)
            .onSubmit { store.edit(item.id, text: editText); editing = nil }
            .onExitCommand { editing = nil }
        } else {
          Text(item.text)
            .strikethrough(item.isDone)
            .foregroundStyle(item.isDone ? .secondary : .primary)
            .onTapGesture(count: 2) { editing = item.id; editText = item.text }
        }
        HStack(spacing: 6) {
          if let source = Self.sourceLabel(appName: item.appName, title: item.windowTitle, url: item.url) {
            Button(source) { onOpenSource(item) }.buttonStyle(.link).lineLimit(1)
          }
          Text(item.createdAt.formatted(.relative(presentation: .named)))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
    .contextMenu {
      Button("编辑") { editing = item.id; editText = item.text }
      Button("删除", role: .destructive) { store.delete(item.id) }
    }
  }

  /// "example.com" for a page, "Window title — App" otherwise.
  static func sourceLabel(appName: String?, title: String?, url: String?) -> String? {
    if let url, let host = URL(string: url)?.host() { return host }
    switch (title, appName) {
    case let (t?, a?): return "\(t) — \(a)"
    case let (t?, nil): return t
    case let (nil, a?): return a
    default: return nil
    }
  }
}
```

- [ ] **Step 2: 面板窗口**

`App/Todo/TodoPanelController.swift`：

```swift
import AppKit
import SwiftUI
import PingCore

/// The todo panel sliding in from the right edge of a screen. It takes keyboard focus without
/// activating the app (like Spotlight), and closes on Esc or a click elsewhere.
@MainActor
final class TodoPanelController {
  private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
  }

  static let width: CGFloat = 360
  private let store: TodoStore
  private let draft = TodoDraft()
  private var panel: KeyPanel?
  private var outsideClickMonitor: Any?
  /// Increments per summon so a late browser URL only lands on the capture it belongs to.
  private var captureID = 0

  init(store: TodoStore) { self.store = store }

  var isVisible: Bool { panel?.isVisible ?? false }

  /// Shows the panel on `screen` with a fresh context. Returns the capture id for `updateURL`.
  @discardableResult
  func show(on screen: NSScreen, context: TodoContext) -> Int {
    captureID += 1
    draft.context = context
    draft.focusToken += 1
    let panel = self.panel ?? makePanel()
    self.panel = panel
    let visible = screen.visibleFrame
    let target = CGRect(x: visible.maxX - Self.width, y: visible.minY, width: Self.width, height: visible.height)
    if !panel.isVisible {
      panel.setFrame(target.offsetBy(dx: Self.width, dy: 0), display: false)
      panel.makeKeyAndOrderFront(nil)
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        panel.animator().setFrame(target, display: true)
      }
      outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        MainActor.assumeIsolated { self?.hide() }
      }
    } else {
      panel.setFrame(target, display: true)
      panel.makeKeyAndOrderFront(nil)
    }
    return captureID
  }

  func updateURL(_ url: String, capture: Int) {
    guard capture == captureID else { return }
    draft.context.url = url
  }

  func hide() {
    guard let panel, panel.isVisible else { return }
    if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
    outsideClickMonitor = nil
    let off = panel.frame.offsetBy(dx: Self.width, dy: 0)
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.15
      panel.animator().setFrame(off, display: true)
    }, completionHandler: {
      MainActor.assumeIsolated { panel.orderOut(nil) }
    })
  }

  private func makePanel() -> KeyPanel {
    let p = KeyPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 600),
                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.hidesOnDeactivate = false
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    let blur = NSVisualEffectView()
    blur.material = .sidebar
    blur.blendingMode = .behindWindow
    blur.state = .active
    let host = NSHostingView(rootView: TodoPanelView(draft: draft, store: store,
                                                     onClose: { [weak self] in self?.hide() },
                                                     onOpenSource: { [weak self] in self?.openSource($0) }))
    host.translatesAutoresizingMaskIntoConstraints = false
    blur.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
      host.topAnchor.constraint(equalTo: blur.topAnchor),
      host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
    ])
    p.contentView = blur
    return p
  }

  /// Takes the user back: the page if there is one, else the app.
  private func openSource(_ item: TodoItem) {
    hide()
    if let s = item.url, let url = URL(string: s) {
      NSWorkspace.shared.open(url)
    } else if let id = item.bundleID, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
      NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
  }
}
```

- [ ] **Step 3: TodoPanelAction**

`App/Actions/TodoPanelAction.swift`：

```swift
import AppKit
import PingCore

/// On My Way: slide in the todo panel on the ping's screen, with the current app, window and page attached.
@MainActor
final class TodoPanelAction: PingAction {
  private let panel: TodoPanelController

  init(panel: TodoPanelController) { self.panel = panel }

  func perform(_ signal: PingSignal) {
    var capture = 0
    // Capture before showing: once the panel has focus, the front app context is ours.
    let context = ContextCapture.capture { [weak self] url in self?.panel.updateURL(url, capture: capture) }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let p = ScreenMath.appKitPoint(fromGlobal: CGPoint(x: signal.point.x, y: signal.point.y), primaryHeight: primaryHeight)
    let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    capture = panel.show(on: screen, context: context)
  }
}
```

（`capture` 在闭包里按引用捕获：网址总是晚于 `show` 返回到达——`ContextCapture` 在后台任务里取网址，主线程在 `show` 返回前不会处理它的回调——所以回调读到的是本次的 id。）

- [ ] **Step 4: 编译应用**

Expected: 成功。若 Swift 6 对 `var capture` 被 `@MainActor` 闭包捕获报错，改为在 `TodoPanelAction` 上存 `private var lastCapture = 0`，闭包读 `self?.lastCapture`，`perform` 末尾赋值 `lastCapture = panel.show(...)`，并在报告中说明。

- [ ] **Step 5: Commit**

```bash
git add App/Todo/TodoPanelView.swift App/Todo/TodoPanelController.swift App/Actions/TodoPanelAction.swift
git commit -m "On My Way slides in a todo panel with context and jump-back links

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 接线与试用（**用户确认节点**）

**Files:**
- Modify: `App/AppCoordinator.swift`

- [ ] **Step 1: 注册 ActionRouter**

在 `AppCoordinator` 中新增存储属性（放在 `private let gate = AccessibilityGate()` 之后）：

```swift
  private let todoStore = TodoStore(fileURL: TodoStore.defaultURL)
  private lazy var todoPanel = TodoPanelController(store: todoStore)
```

在 `init()` 里 `bus.register(PingEffectHandler(...))` 那一行之后加：

```swift
    bus.register(ActionRouter(actions: [
      .claudeQuickEntry: ClaudeQuickEntryAction(),
      .todoPanel: TodoPanelAction(panel: todoPanel),
      .retreat: RetreatAction(),
    ]))
```

（`PingEffectHandler` 先注册，所以动画与音效总在动作之前。）

- [ ] **Step 2: 跑测试、编译应用**

Expected: 测试全绿（67 + 2 + 6 + 6 = 81）；编译成功。

- [ ] **Step 3: Commit**

```bash
git add App/AppCoordinator.swift
git commit -m "Wire ping actions into the signal bus

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: 重启应用并手动检查（控制者执行，用户参与）**

```bash
pkill -f "Debug/ping-signals.app/Contents/MacOS/ping-signals"; sleep 1
open build/Build/Products/Debug/ping-signals.app
```

手动清单（设计文档第 7 节）：
1. **请求协助**（经典：⌥+向下拖）：松开 ⌥ 后约 0.1 s 出现 Claude 快速输入框；Claude 未运行时先启动、约 3 s 后出现
2. **正在路上**（经典：⌥+向右拖）：右侧滑出面板，可直接打字，回车保存，Esc / 点外面收起；在 Safari、Chrome、Arc 里打时来源显示域名（首次弹出「自动化」授权），在 Finder / 其他应用里显示「窗口标题 — 应用」；点来源能跳回
3. 勾选完成、双击编辑、右键删除；关掉再打开应用后待办还在
4. **危险**（经典：⌥+向上拖）：所有窗口隐藏；再打一次恢复，原来最前面的应用回到最前；往返 3 次一致；撤退状态下轮盘仍可用
5. **问号**、**普通标记**、菜单「预览标记」：只有动画与音效，不触发任何动作（预览「危险」不撤退）

- [ ] **Step 5: 🔶 用户确认节点**

用户试用并确认三个动作的行为与面板外观；按反馈调整后再结束。
