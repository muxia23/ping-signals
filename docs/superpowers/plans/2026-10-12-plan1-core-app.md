# ping-signals Plan 1：核心应用 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出可日常使用的 Swift 原生标记轮盘：⌥+拖动 → 轮盘（经典 4 格 / 新版 8 格）→ 松开出标记动画 + 音效；菜单栏可暂停、切换风格、预览标记；信号接口就位；性能达标。

**Architecture:** 纯逻辑放在 `PingCore` 框架（手势状态机、按键映射、扇区几何、标记目录、设置、信号总线），用 Swift Testing 做单元测试；`ping-signals` 应用负责系统交互（CGEventTap、透明覆盖窗口、Core Graphics 绘制轮盘、Core Animation 标记动画、AVAudioEngine 音效、菜单栏）。数据单向流动：EventTap → GestureMachine → AppCoordinator → Overlay / SignalBus → PingEffectHandler。

**Tech Stack:** Swift 6、AppKit、Core Graphics、Core Animation、AVFoundation、XcodeGen 2.45、Xcode 26、Swift Testing，macOS 14+。

**设计文档：** `docs/superpowers/specs/2026-10-12-ping-signals-design.md`
**原版参考：** `~/sandbox/lolping-fork/`（`native/hook-helper/src/decision.cpp` 是手势逻辑的移植来源）

**不在本计划内：** SwiftUI 设置窗口、轮盘编辑器、开机自启、快捷键录制、多语言、授权引导窗口（Plan 2）；Sparkle、发布脚本（Plan 3）。本计划中设置只能通过菜单栏改「启用 / 风格」，其余取默认值。

---

## 文件结构

```
ping-signals/
├── project.yml                         XcodeGen 工程定义
├── .gitignore
├── scripts/
│   ├── make-cert.sh                    一次性创建本地自签名代码签名证书
│   ├── import-assets.sh                从参考目录复制贴图、把音效转为 m4a
│   └── measure.sh                      性能测量（内存 + 平均 CPU）
├── Core/                               PingCore 框架（纯逻辑，无 AppKit）
│   ├── Input/KeyMap.swift              VK 常量、mac keyCode↔VK、修饰键 flags 转换
│   ├── Input/GestureTypes.swift        InputEvent / Trigger / Hotkey / GestureConfig / GestureOutput
│   ├── Input/GestureMachine.swift      手势状态机（移植 decision.cpp）
│   ├── Geometry/WheelGeometry.swift    pickSlice
│   ├── Geometry/ScreenMath.swift       全局坐标（左上原点）↔ AppKit 坐标
│   ├── Model/PingCatalog.swift         PingID / WheelStyle / PingDef / 两种风格的目录
│   ├── Model/Settings.swift            Settings（宽容解码）+ SettingsStore
│   └── Signals/SignalBus.swift         PingSignal / SignalHandler / SignalBus
├── App/                                ping-signals 应用
│   ├── main.swift                      入口；--render-wheels 预览模式
│   ├── AppDelegate.swift
│   ├── AppCoordinator.swift            串联各模块
│   ├── MenuBarController.swift
│   ├── AccessibilityGate.swift
│   ├── Input/EventTap.swift
│   ├── Input/FullscreenProbe.swift
│   ├── Overlay/Drawing.swift           y 向下的 CGContext 工具、贴图加载、着色
│   ├── Overlay/WheelArt.swift          WheelArt 结构 + 预览导出
│   ├── Overlay/ModernWheelRenderer.swift
│   ├── Overlay/ClassicWheelRenderer.swift
│   ├── Overlay/WheelLayer.swift        轮盘图层（打开 / 高亮 / 关闭）
│   ├── Overlay/OverlayController.swift 每屏一个透明面板
│   ├── Overlay/ModernPingAnimator.swift
│   ├── Overlay/ClassicPingAnimator.swift
│   ├── Audio/SoundPlayer.swift
│   ├── Signals/PingEffectHandler.swift
│   └── Resources/{Textures,Sounds}/    由 import-assets.sh 生成并入库
└── Tests/                              PingCoreTests（Swift Testing）
    ├── KeyMapTests.swift
    ├── GestureMachineTests.swift
    ├── WheelGeometryTests.swift
    ├── ScreenMathTests.swift
    ├── PingCatalogTests.swift
    ├── SettingsTests.swift
    └── SignalBusTests.swift
```

**通用命令**（在 `~/sandbox/ping-signals` 下执行）：

- 生成工程：`xcodegen generate`
- 跑测试：`xcodebuild test -project PingSignals.xcodeproj -scheme PingSignals -destination 'platform=macOS,arch=arm64' -derivedDataPath build -quiet 2>&1 | tail -30`
- 编译应用：`xcodebuild build -project PingSignals.xcodeproj -scheme PingSignals -configuration Debug -derivedDataPath build -quiet 2>&1 | tail -30`，产物 `build/Build/Products/Debug/ping-signals.app`

下文简称 **「跑测试」「编译应用」**。

---

### Task 1: 工程骨架与本地签名证书

**Files:**
- Create: `scripts/make-cert.sh`, `project.yml`, `.gitignore`, `App/main.swift`, `App/AppDelegate.swift`, `Core/Input/KeyMap.swift`（先只放 VK 常量）, `Tests/KeyMapTests.swift`

- [ ] **Step 1: 写证书脚本**

`scripts/make-cert.sh`：

```bash
#!/bin/bash
# Creates the self-signed code-signing identity every build is signed with (run once).
# A stable identity lets macOS keep the Accessibility grant across rebuilds and updates.
set -euo pipefail
NAME="ping-signals Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "Identity already exists: $NAME"; exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout pass:ps -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P ps -T /usr/bin/codesign
# Asks for the login password once (GUI prompt): trusts the certificate for code signing.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"
security find-identity -v -p codesigning | grep "$NAME"
```

- [ ] **Step 2: 运行证书脚本**

Run: `chmod +x scripts/make-cert.sh && scripts/make-cert.sh`
Expected: 弹出系统密码框（用户输入登录密码），最后打印一行 `1) <hash> "ping-signals Local Signing"`。
**这一步需要用户在场输入密码。**

- [ ] **Step 3: 写 project.yml**

```yaml
name: PingSignals
options:
  bundleIdPrefix: com.muxia
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "ping-signals Local Signing"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: NO
targets:
  PingCore:
    type: framework
    platform: macOS
    sources: [Core]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.muxia.ping-signals.core
        GENERATE_INFOPLIST_FILE: YES
  PingSignals:
    type: application
    platform: macOS
    sources: [App]
    dependencies:
      - target: PingCore
    info:
      path: App/Info.plist
      properties:
        CFBundleName: ping-signals
        CFBundleDisplayName: ping-signals
        LSUIElement: true
        LSMinimumSystemVersion: "14.0"
        NSHumanReadableCopyright: "MIT. Ported from darrenprx/lolPing. League of Legends assets © Riot Games."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.muxia.ping-signals
        PRODUCT_NAME: ping-signals
  PingCoreTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: PingCore
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.muxia.ping-signals.tests
schemes:
  PingSignals:
    build:
      targets:
        PingSignals: all
        PingCoreTests: [test]
    test:
      targets: [PingCoreTests]
```

- [ ] **Step 4: 写 .gitignore**

```gitignore
*.xcodeproj/
build/
App/Info.plist
.DS_Store
```

- [ ] **Step 5: 写最小应用入口**

`App/main.swift`：

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`App/AppDelegate.swift`：

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog("ping-signals launched")
  }
}
```

- [ ] **Step 6: 写第一个失败测试（VK 常量）**

`Tests/KeyMapTests.swift`：

```swift
import Testing
@testable import PingCore

@Suite struct KeyMapTests {
  @Test func vkConstants() {
    #expect(VK.lOption == 0xA4)
    #expect(VK.lControl == 0xA2)
    #expect(VK.escape == 0x1B)
  }
}
```

- [ ] **Step 7: 生成工程并跑测试，确认失败**

Run: `xcodegen generate && ` 跑测试
Expected: 编译失败，`cannot find 'VK' in scope`。

- [ ] **Step 8: 写 VK 常量**

`Core/Input/KeyMap.swift`：

```swift
/// Keys are identified by Windows virtual-key codes throughout PingCore, as in the original lolPing helper,
/// so its tests port unchanged. KeyMap translates macOS key codes and modifier flags into them.
public enum VK {
  public static let backspace: UInt32 = 0x08, tab: UInt32 = 0x09, enter: UInt32 = 0x0D
  public static let shift: UInt32 = 0x10, control: UInt32 = 0x11, option: UInt32 = 0x12
  public static let capsLock: UInt32 = 0x14, escape: UInt32 = 0x1B, space: UInt32 = 0x20
  public static let lShift: UInt32 = 0xA0, rShift: UInt32 = 0xA1
  public static let lControl: UInt32 = 0xA2, rControl: UInt32 = 0xA3
  public static let lOption: UInt32 = 0xA4, rOption: UInt32 = 0xA5
  public static let lCommand: UInt32 = 0x5B, rCommand: UInt32 = 0x5C
}
```

- [ ] **Step 9: 跑测试确认通过；编译应用确认能签名**

Run: 跑测试 → Expected: `Test Suite 'All tests' passed`（或 `** TEST SUCCEEDED **`）。
Run: 编译应用，然后 `codesign -dv build/Build/Products/Debug/ping-signals.app 2>&1 | grep Authority`
Expected: `Authority=ping-signals Local Signing`

- [ ] **Step 10: Commit**

```bash
git add project.yml .gitignore scripts/make-cert.sh App Core Tests
git commit -m "Scaffold XcodeGen project, local signing identity script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: KeyMap（keyCode↔VK、修饰键 flags）

移植 `lolping-fork/native/hook-helper/src/macinput.cpp`。

**Files:**
- Modify: `Core/Input/KeyMap.swift`
- Modify: `Tests/KeyMapTests.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/KeyMapTests.swift` 的 `KeyMapTests` 里追加：

```swift
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'KeyMap' in scope`。

- [ ] **Step 3: 实现**

在 `Core/Input/KeyMap.swift` 末尾追加：

```swift
public struct KeyTransition: Equatable, Sendable {
  public let vk: UInt32
  public let down: Bool
  public init(vk: UInt32, down: Bool) { self.vk = vk; self.down = down }
}

public enum KeyMap {
  /// CGEventFlags bits: device-independent masks and the NX_DEVICE* left/right bits.
  public enum Flag {
    public static let shift: UInt64 = 0x0002_0000, control: UInt64 = 0x0004_0000
    public static let option: UInt64 = 0x0008_0000, command: UInt64 = 0x0010_0000
    public static let devLCtrl: UInt64 = 0x0001, devLShift: UInt64 = 0x0002, devRShift: UInt64 = 0x0004
    public static let devLCmd: UInt64 = 0x0008, devRCmd: UInt64 = 0x0010, devLAlt: UInt64 = 0x0020
    public static let devRAlt: UInt64 = 0x0040, devRCtrl: UInt64 = 0x2000
    /// Every bit modifierTransitions looks at.
    public static let all: UInt64 = shift | control | option | command | devLCtrl | devLShift | devRShift
      | devLCmd | devRCmd | devLAlt | devRAlt | devRCtrl
  }

  /// kVK_* (Carbon Events.h) → VK. Modifiers are listed so vkToKeyCode can answer for them.
  private static let keys: [(code: UInt16, vk: UInt32)] = [
    (0x00, 0x41), (0x0B, 0x42), (0x08, 0x43), (0x02, 0x44), (0x0E, 0x45), (0x03, 0x46), (0x05, 0x47), (0x04, 0x48),
    (0x22, 0x49), (0x26, 0x4A), (0x28, 0x4B), (0x25, 0x4C), (0x2E, 0x4D), (0x2D, 0x4E), (0x1F, 0x4F), (0x23, 0x50),
    (0x0C, 0x51), (0x0F, 0x52), (0x01, 0x53), (0x11, 0x54), (0x20, 0x55), (0x09, 0x56), (0x0D, 0x57), (0x07, 0x58),
    (0x10, 0x59), (0x06, 0x5A),
    (0x1D, 0x30), (0x12, 0x31), (0x13, 0x32), (0x14, 0x33), (0x15, 0x34), (0x17, 0x35), (0x16, 0x36), (0x1A, 0x37),
    (0x1C, 0x38), (0x19, 0x39),
    (0x7A, 0x70), (0x78, 0x71), (0x63, 0x72), (0x76, 0x73), (0x60, 0x74), (0x61, 0x75), (0x62, 0x76),
    (0x64, 0x77), (0x65, 0x78), (0x6D, 0x79), (0x67, 0x7A), (0x6F, 0x7B), (0x69, 0x7C), (0x6B, 0x7D),
    (0x71, 0x7E), (0x6A, 0x7F), (0x40, 0x80), (0x4F, 0x81), (0x50, 0x82), (0x5A, 0x83),  // F1-F20
    (0x24, 0x0D), (0x4C, 0x0D),                                                          // Return, keypad Enter
    (0x30, 0x09), (0x31, 0x20), (0x33, 0x08), (0x35, 0x1B), (0x75, 0x2E), (0x72, 0x2D),  // Tab Space ⌫ Esc ⌦ Help
    (0x73, 0x24), (0x77, 0x23), (0x74, 0x21), (0x79, 0x22),                              // Home End PgUp PgDn
    (0x7B, 0x25), (0x7E, 0x26), (0x7C, 0x27), (0x7D, 0x28),                              // arrows
    (0x32, 0xC0), (0x1B, 0xBD), (0x18, 0xBB), (0x21, 0xDB), (0x1E, 0xDD), (0x2A, 0xDC),  // ` - = [ ] backslash
    (0x29, 0xBA), (0x27, 0xDE), (0x2B, 0xBC), (0x2F, 0xBE), (0x2C, 0xBF),                // ; ' , . /
    (0x52, 0x60), (0x53, 0x61), (0x54, 0x62), (0x55, 0x63), (0x56, 0x64), (0x57, 0x65), (0x58, 0x66),
    (0x59, 0x67), (0x5B, 0x68), (0x5C, 0x69),                                            // keypad 0-9
    (0x43, 0x6A), (0x45, 0x6B), (0x4E, 0x6D), (0x41, 0x6E), (0x4B, 0x6F),                // keypad * + - . /
    (0x39, 0x14),                                                                        // Caps Lock
    (0x38, 0xA0), (0x3C, 0xA1), (0x3B, 0xA2), (0x3E, 0xA3), (0x3A, 0xA4), (0x3D, 0xA5),  // modifiers
    (0x37, 0x5B), (0x36, 0x5C),
  ]

  private struct Modifier { let vk: UInt32; let group: UInt64; let mine: UInt64; let other: UInt64 }
  private static let modifiers: [Modifier] = [
    Modifier(vk: VK.lShift, group: Flag.shift, mine: Flag.devLShift, other: Flag.devRShift),
    Modifier(vk: VK.rShift, group: Flag.shift, mine: Flag.devRShift, other: Flag.devLShift),
    Modifier(vk: VK.lControl, group: Flag.control, mine: Flag.devLCtrl, other: Flag.devRCtrl),
    Modifier(vk: VK.rControl, group: Flag.control, mine: Flag.devRCtrl, other: Flag.devLCtrl),
    Modifier(vk: VK.lOption, group: Flag.option, mine: Flag.devLAlt, other: Flag.devRAlt),
    Modifier(vk: VK.rOption, group: Flag.option, mine: Flag.devRAlt, other: Flag.devLAlt),
    Modifier(vk: VK.lCommand, group: Flag.command, mine: Flag.devLCmd, other: Flag.devRCmd),
    Modifier(vk: VK.rCommand, group: Flag.command, mine: Flag.devRCmd, other: Flag.devLCmd),
  ]

  /// macOS key code → VK; 0 when the key has no VK equivalent.
  public static func keyCodeToVK(_ code: UInt16) -> UInt32 {
    keys.first { $0.code == code }?.vk ?? 0
  }

  /// VK → macOS key code; nil when there is none.
  public static func vkToKeyCode(_ vk: UInt32) -> UInt16? {
    keys.first { $0.vk == vk }?.code
  }

  /// Whether modifier key `vk` is held according to `flags`. Synthetic events often carry only the
  /// device-independent mask: that counts as the left key.
  public static func modifierHeld(_ flags: UInt64, _ vk: UInt32) -> Bool {
    guard let m = modifiers.first(where: { $0.vk == vk }) else { return false }
    if flags & m.group == 0 { return false }
    if flags & m.mine != 0 { return true }
    let isLeft = vk == VK.lShift || vk == VK.lControl || vk == VK.lOption || vk == VK.lCommand
    return isLeft && flags & m.other == 0
  }

  /// The modifier key-ups, then key-downs, that turn `old` into `new`.
  public static func modifierTransitions(from old: UInt64, to new: UInt64) -> [KeyTransition] {
    var ups: [KeyTransition] = [], downs: [KeyTransition] = []
    for m in modifiers {
      let was = modifierHeld(old, m.vk), now = modifierHeld(new, m.vk)
      if was && !now { ups.append(KeyTransition(vk: m.vk, down: false)) }
      if !was && now { downs.append(KeyTransition(vk: m.vk, down: true)) }
    }
    return ups + downs
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Core/Input/KeyMap.swift Tests/KeyMapTests.swift
git commit -m "Port macOS key code and modifier flag mapping

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: GestureMachine（手势状态机）

移植 `decision.{h,cpp}`，去掉表情轮盘（第二个触发键）、Windows 菜单键屏蔽、Caps Lock 触发。

**Files:**
- Create: `Core/Input/GestureTypes.swift`, `Core/Input/GestureMachine.swift`, `Tests/GestureMachineTests.swift`

- [ ] **Step 1: 写类型**

`Core/Input/GestureTypes.swift`：

```swift
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
```

- [ ] **Step 2: 写失败测试**

`Tests/GestureMachineTests.swift`（用例移植自 `helper_tests.cpp`，去掉表情、菜单键屏蔽、Caps Lock、JSON 相关用例；mac 不屏蔽菜单键，所以松开 ⌥ 时不再有注入）：

```swift
import Testing
@testable import PingCore

private let ALT = VK.lOption, CTRL = VK.lControl, CMD = VK.lCommand
private let KEY_P: UInt32 = 0x50, KEY_V: UInt32 = 0x56, ESC = VK.escape, TAB = VK.tab

private func kd(_ vk: UInt32) -> InputEvent { InputEvent(kind: .keyDown, vk: vk) }
private func ku(_ vk: UInt32) -> InputEvent { InputEvent(kind: .keyUp, vk: vk) }
private func md(_ b: MouseButton, _ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseDown, button: b, x: x, y: y, timeMs: t) }
private func mu(_ b: MouseButton, _ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseUp, button: b, x: x, y: y, timeMs: t) }
private func mv(_ x: Int, _ y: Int, _ t: UInt64 = 0) -> InputEvent { InputEvent(kind: .mouseMove, x: x, y: y, timeMs: t) }

private func machine(_ trigger: Trigger = .option, clickPing: Bool = false, gameCheck: Bool = false) -> GestureMachine {
  var c = GestureConfig()
  c.trigger = trigger
  c.clickPing = clickPing
  c.gameCheck = gameCheck
  let m = GestureMachine()
  _ = m.setConfig(c)
  return m
}

/// ⌥ held, left pressed at (100,100), dragged to (130,100): the wheel is open.
private func openWheel(_ m: GestureMachine) {
  _ = m.onEvent(kd(ALT)); _ = m.onEvent(md(.left, 100, 100)); _ = m.onEvent(mv(130, 100))
}

private func hasCancel(_ o: GestureOutput) -> Bool { o.emits.contains(.cancel) }
private func clickPoint(_ o: GestureOutput) -> GesturePoint? {
  for e in o.emits { if case .click(let p) = e { return p } }
  return nil
}
private func releasePoint(_ o: GestureOutput) -> GesturePoint? {
  for e in o.emits { if case .wheelRelease(let p) = e { return p } }
  return nil
}
private func opened(_ o: GestureOutput) -> Bool {
  o.emits.contains { if case .wheelOpen = $0 { return true } else { return false } }
}

@Suite struct GestureMachineTests {
  @Test func altDragOpensWheelAndReleases() {
    let m = GestureMachine()
    #expect(!m.onEvent(kd(ALT)).swallow)
    var r = m.onEvent(md(.left, 100, 100))
    #expect(r.swallow)
    #expect(m.state == .pending)
    r = m.onEvent(mv(104, 104))  // 5.7 px, below the 8 px threshold
    #expect(!r.swallow && r.emits.isEmpty)
    r = m.onEvent(mv(120, 100))
    #expect(!r.swallow)
    #expect(m.state == .wheel)
    #expect(r.emits == [.wheelOpen(GesturePoint(100, 100)), .wheelMove(GesturePoint(120, 100))])
    r = m.onEvent(mv(125, 90))
    #expect(r.emits == [.wheelMove(GesturePoint(125, 90))])
    r = m.onEvent(mu(.left, 130, 90))
    #expect(r.swallow)
    #expect(releasePoint(r) == GesturePoint(130, 90))
    #expect(m.state == .idle)
  }

  @Test func plainClickPassesThrough() {
    let m = GestureMachine()
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(!m.onEvent(mu(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func altClickReplaysWhenClickPingOff() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(md(.left, 50, 60)).swallow)
    _ = m.onEvent(mv(53, 62))  // tiny jitter, still a click
    let r = m.onEvent(mu(.left, 53, 62))
    #expect(r.swallow)
    #expect(r.emits.isEmpty)
    #expect(r.replays == [.buttonDown(.left), .buttonUp(.left)])
    #expect(m.state == .idle)
  }

  @Test func altClickPingsWhenClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 50, 60))
    let r = m.onEvent(mu(.left, 51, 60))
    #expect(r.swallow)
    #expect(r.replays.isEmpty)
    #expect(clickPoint(r) == GesturePoint(50, 60))
  }

  @Test func rightClickCancelsWheel() {
    let m = GestureMachine()
    openWheel(m)
    var r = m.onEvent(md(.right, 130, 100))
    #expect(r.swallow)
    #expect(hasCancel(r))
    #expect(m.onEvent(mu(.right, 130, 100)).swallow)
    r = m.onEvent(mu(.left, 130, 100))
    #expect(r.swallow)
    #expect(releasePoint(r) == nil)
    #expect(m.state == .idle)
  }

  @Test func rightClickWithAltButNoGesturePasses() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(md(.right, 1, 1)).swallow)
    #expect(!m.onEvent(mu(.right, 1, 1)).swallow)
  }

  @Test func escapeCancelsWheel() {
    let m = GestureMachine()
    openWheel(m)
    var r = m.onEvent(kd(ESC))
    #expect(r.swallow)
    #expect(hasCancel(r))
    #expect(m.onEvent(ku(ESC)).swallow)
    r = m.onEvent(mu(.left, 130, 100))
    #expect(r.swallow && r.emits.isEmpty)
  }

  @Test func triggerReleasedDuringWheelCancels() {
    let m = GestureMachine()
    openWheel(m)
    let r = m.onEvent(ku(ALT))
    #expect(hasCancel(r))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func triggerReleasedDuringPendingReplaysPress() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100))
    let r = m.onEvent(ku(ALT))
    #expect(!r.swallow)  // macOS has no menu-key mask: the ⌥-up passes
    #expect(r.replays == [.buttonDown(.left)])
    #expect(m.state == .idle)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)  // the real up completes the replayed click
  }

  @Test func triggerReleasedDuringPendingPingsWhenClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100))
    let r = m.onEvent(ku(ALT))
    #expect(clickPoint(r) == GesturePoint(100, 100))
    #expect(m.onEvent(mu(.left, 100, 100)).swallow)
  }

  /// ⌥+Tab belongs to another program: clicks pass while the chord lasts.
  @Test func altTabClicksPassThrough() {
    let m = GestureMachine()
    #expect(!m.onEvent(kd(ALT)).swallow)
    #expect(!m.onEvent(kd(TAB)).swallow)
    #expect(!m.onEvent(ku(TAB)).swallow)
    var r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    r = m.onEvent(ku(ALT))
    #expect(!r.swallow && r.replays.isEmpty)
    _ = m.onEvent(kd(ALT))  // the chord is over: ⌥+click gestures again
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow)
    #expect(r.replays.count == 2)
  }

  @Test func altTabClickPlacesNoPingEvenWithClickPingOn() {
    let m = machine(clickPing: true)
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(kd(TAB))
    let r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
  }

  @Test func commandTabClicksPassAndSyncClearsFlag() {
    let m = machine(.command)
    _ = m.onEvent(kd(CMD))
    _ = m.onEvent(kd(TAB))
    #expect(!m.onEvent(md(.left, 100, 100)).swallow)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    m.syncKeyStates { _ in false }  // the OS reports every key up
    _ = m.onEvent(kd(CMD))
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
  }

  @Test func fullscreenGameKeepsTheClick() {
    let m = machine(clickPing: true, gameCheck: true)
    var fullscreen = true
    m.fullscreenProbe = { _, _ in fullscreen }
    _ = m.onEvent(kd(ALT))
    var r = m.onEvent(md(.left, 100, 100))
    #expect(!r.swallow)
    #expect(clickPoint(r) == nil)
    #expect(!m.onEvent(mu(.left, 100, 100)).swallow)
    fullscreen = false
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow)
    #expect(clickPoint(r) != nil)
    #expect(m.state == .idle)
  }

  @Test func fullscreenProbeIgnoredWhenDisabled() {
    let m = machine(clickPing: true, gameCheck: false)
    var consulted = false
    m.fullscreenProbe = { _, _ in consulted = true; return true }
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(md(.left, 100, 100)).swallow)
    #expect(!consulted)
    #expect(clickPoint(m.onEvent(mu(.left, 100, 100))) != nil)
  }

  @Test func altUpAfterGestureIsNotTouched() {
    let m = GestureMachine()
    openWheel(m)
    _ = m.onEvent(mu(.left, 130, 100))
    let r = m.onEvent(ku(ALT))
    #expect(!r.swallow && r.replays.isEmpty)
  }

  @Test func toggleHotkeyDisablesAndEnables() {
    let m = GestureMachine()
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    var r = m.onEvent(kd(KEY_P))
    #expect(r.swallow)
    #expect(r.emits == [.toggled(false)])
    #expect(!m.enabled)
    #expect(m.onEvent(ku(KEY_P)).swallow)
    _ = m.onEvent(ku(CTRL))
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)  // disabled: ⌥+press passes
    _ = m.onEvent(mu(.left, 1, 1))
    _ = m.onEvent(kd(CTRL))
    r = m.onEvent(kd(KEY_P))
    #expect(r.emits == [.toggled(true)])
    #expect(m.enabled)
  }

  @Test func hotkeyAutorepeatTogglesOnce() {
    let m = GestureMachine()
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    #expect(m.onEvent(kd(KEY_P)).emits == [.toggled(false)])
    let repeatOut = m.onEvent(kd(KEY_P))
    #expect(repeatOut.swallow)
    #expect(repeatOut.emits.isEmpty)
    #expect(!m.enabled)
  }

  @Test func hotkeyIgnoredWhileSuspended() {
    let m = GestureMachine()
    _ = m.setSuspended(true)
    _ = m.onEvent(kd(CTRL))
    _ = m.onEvent(kd(ALT))
    let r = m.onEvent(kd(KEY_P))
    #expect(!r.swallow && r.emits.isEmpty)
    #expect(m.enabled)
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
  }

  @Test func disablingMidDragCancelsAndSwallowsUp() {
    let m = GestureMachine()
    openWheel(m)
    #expect(hasCancel(m.setEnabled(false)))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func configChangeMidDragCancels() {
    let m = GestureMachine()
    openWheel(m)
    #expect(hasCancel(m.setConfig(GestureConfig())))
    #expect(m.state == .swallowUp)
  }

  @Test func lostUpRecoversOnNextPress() {
    let m = GestureMachine()
    openWheel(m)
    _ = m.setEnabled(false)
    _ = m.setEnabled(true)
    #expect(m.onEvent(md(.left, 5, 5)).swallow)  // ⌥ still held
    #expect(m.state == .pending)
  }

  @Test func lostRightUpDoesNotSwallowNextClick() {
    let m = GestureMachine()
    openWheel(m)
    #expect(m.onEvent(md(.right, 130, 100)).swallow)
    _ = m.onEvent(mu(.left, 130, 100))
    #expect(m.state == .idle)
    #expect(!m.onEvent(md(.right, 5, 5)).swallow)
    #expect(!m.onEvent(mu(.right, 5, 5)).swallow)
  }

  @Test func lostKeyUpDoesNotSwallowNextPress() {
    let m = GestureMachine()
    openWheel(m)
    #expect(m.onEvent(kd(ESC)).swallow)
    _ = m.onEvent(mu(.left, 130, 100))
    _ = m.onEvent(ku(ALT))
    #expect(m.state == .idle)
    #expect(!m.onEvent(kd(ESC)).swallow)
    #expect(!m.onEvent(ku(ESC)).swallow)
  }

  @Test func buttonHeldBeforeTriggerPassesUp() {
    let m = GestureMachine()
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(mv(50, 50)).swallow)
    #expect(!m.onEvent(mu(.left, 50, 50)).swallow)
    #expect(m.state == .idle)
  }

  @Test func watchdogCancelsStaleGesture() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100, 1000))
    _ = m.onEvent(mv(130, 100, 1100))
    #expect(m.tick(nowMs: 5000).emits.isEmpty)
    #expect(hasCancel(m.tick(nowMs: 1100 + GestureMachine.watchdogMs + 1)))
    #expect(m.state == .swallowUp)
    #expect(m.onEvent(mu(.left, 130, 100)).swallow)
    #expect(m.state == .idle)
  }

  @Test func watchdogFromPendingSwallowsLaterUp() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    _ = m.onEvent(md(.left, 100, 100, 1000))
    #expect(m.state == .pending)
    #expect(m.tick(nowMs: 1000 + GestureMachine.watchdogMs).emits.isEmpty)  // exactly at the limit
    #expect(hasCancel(m.tick(nowMs: 1000 + GestureMachine.watchdogMs + 1)))
    #expect(m.state == .swallowUp)
    let r = m.onEvent(mu(.left, 100, 100))
    #expect(r.swallow && r.emits.isEmpty && r.replays.isEmpty)
    #expect(m.state == .idle)
  }

  @Test func syncClearsStaleTrigger() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    m.syncKeyStates { _ in false }
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func syncKeepsKeysThatAreStillDown() {
    let m = GestureMachine()
    _ = m.onEvent(kd(ALT))
    m.syncKeyStates { $0 == ALT }
    #expect(m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .pending)
  }

  @Test func syncNeverSetsKeys() {
    let m = GestureMachine()
    m.syncKeyStates { _ in true }
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    #expect(m.state == .idle)
  }

  @Test func syncKeepsSwallowedTriggerKey() {
    let m = machine(.key(KEY_V))
    #expect(m.onEvent(kd(KEY_V)).swallow)
    m.syncKeyStates { _ in false }  // the OS never saw V go down
    #expect(m.onEvent(md(.left, 0, 0)).swallow)
    #expect(m.state == .pending)
  }

  @Test func controlTriggerIgnoresOption() {
    let m = machine(.control)
    _ = m.onEvent(kd(ALT))
    #expect(!m.onEvent(md(.left, 1, 1)).swallow)
    _ = m.onEvent(mu(.left, 1, 1))
    _ = m.onEvent(ku(ALT))
    _ = m.onEvent(kd(CTRL))
    #expect(m.onEvent(md(.left, 1, 1)).swallow)
  }

  @Test func customKeyTrigger() {
    let m = machine(.key(KEY_V))
    #expect(m.onEvent(kd(KEY_V)).swallow)
    #expect(m.onEvent(md(.left, 0, 0)).swallow)
    #expect(opened(m.onEvent(mv(0, 40))))
    #expect(releasePoint(m.onEvent(mu(.left, 0, 40))) != nil)
    #expect(m.onEvent(ku(KEY_V)).swallow)
    _ = m.setEnabled(false)
    #expect(!m.onEvent(kd(KEY_V)).swallow)  // disabled: typing V works again
  }

  @Test func mouse4TriggerDragsWithSideButton() {
    let m = machine(.mouse4)
    #expect(!m.onEvent(md(.left, 0, 0)).swallow)
    _ = m.onEvent(mu(.left, 0, 0))
    #expect(m.onEvent(md(.x1, 10, 10)).swallow)
    let r = m.onEvent(mu(.x1, 10, 10))  // click without drag: replay so browser Back still works
    #expect(r.swallow)
    #expect(r.replays == [.buttonDown(.x1), .buttonUp(.x1)])
    _ = m.onEvent(md(.x1, 10, 10))
    #expect(opened(m.onEvent(mv(40, 10))))
    #expect(releasePoint(m.onEvent(mu(.x1, 40, 10))) != nil)
  }

  @Test func optionDragThroughFlagTransitions() {
    // EventTap feeds flag transitions to the machine as key events: ⌥ + drag must open the wheel.
    let m = GestureMachine()
    for t in KeyMap.modifierTransitions(from: 0, to: KeyMap.Flag.option | KeyMap.Flag.devLAlt) {
      _ = m.onEvent(t.down ? kd(t.vk) : ku(t.vk))
    }
    #expect(m.onEvent(md(.left, 10, 10)).swallow)
    #expect(opened(m.onEvent(mv(40, 10))))
  }
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'GestureMachine' in scope`。

- [ ] **Step 4: 实现 GestureMachine**

`Core/Input/GestureMachine.swift`：

```swift
/// Decides what happens to every input event. Pure logic, ported from lolPing's decision.cpp
/// (single wheel, no Windows menu-key masking).
public final class GestureMachine {
  public enum State: Equatable, Sendable { case idle, pending, wheel, swallowUp }
  public static let watchdogMs: UInt64 = 10_000

  public private(set) var state: State = .idle
  public private(set) var enabled = true
  public private(set) var config = GestureConfig()
  /// Does a fullscreen app own the screen under (x, y)? Unset: gameCheck never fires.
  public var fullscreenProbe: ((Int, Int) -> Bool)?

  private var suspended = false
  private var keyDown = [Bool](repeating: false, count: 256)
  private var swallowKeyUps = Set<UInt32>()
  private var swallowRightUp = false
  /// A non-modifier key was pressed while the trigger is held (⌥+Tab, ⌘+Tab...): that chord belongs to
  /// another program, so clicks pass through until the trigger is released.
  private var foreignKey = false
  private var dragButton: MouseButton = .none
  private var px = 0, py = 0
  private var lastMouseMs: UInt64 = 0

  public init() {}

  // MARK: Configuration

  public func setConfig(_ c: GestureConfig) -> GestureOutput {
    var out = GestureOutput()
    cancelGesture(&out)
    config = c
    enabled = c.enabled
    return out
  }

  public func setEnabled(_ on: Bool) -> GestureOutput {
    var out = GestureOutput()
    if !on { cancelGesture(&out) }
    enabled = on
    return out
  }

  public func setSuspended(_ on: Bool) -> GestureOutput {
    var out = GestureOutput()
    if on { cancelGesture(&out) }
    suspended = on
    return out
  }

  public func tick(nowMs: UInt64) -> GestureOutput {
    var out = GestureOutput()
    let busy = state == .pending || state == .wheel
    if busy && nowMs > lastMouseMs && nowMs - lastMouseMs > Self.watchdogMs {
      out.emits.append(.cancel)
      // The press was swallowed, so its up must be swallowed too. If the up was really lost,
      // the next drag-button down resets swallowUp to idle.
      state = .swallowUp
    }
    return out
  }

  /// Forgets keys we believe are down but the OS says are up. Never marks a key as down.
  /// Keys whose down we swallowed are kept: the OS never saw them go down.
  public func syncKeyStates(isDown: (UInt32) -> Bool) {
    for vk in 0..<256 where keyDown[vk] && !swallowKeyUps.contains(UInt32(vk)) && !isDown(UInt32(vk)) {
      keyDown[vk] = false
    }
    if !held() { foreignKey = false }
  }

  // MARK: Events

  public func onEvent(_ e: InputEvent) -> GestureOutput {
    var out = GestureOutput()
    switch e.kind {
    case .keyDown: onKeyDown(e, &out)
    case .keyUp: onKeyUp(e, &out)
    case .mouseDown: lastMouseMs = e.timeMs; onMouseDown(e, &out)
    case .mouseUp: lastMouseMs = e.timeMs; onMouseUp(e, &out)
    case .mouseMove: lastMouseMs = e.timeMs; onMouseMove(e, &out)
    }
    return out
  }

  private func onKeyDown(_ e: InputEvent, _ out: inout GestureOutput) {
    let vk = e.vk & 0xFF
    let isRepeat = keyDown[Int(vk)]
    keyDown[Int(vk)] = true

    // Only in idle: a foreign key mid-gesture (Esc cancelling a wheel) says nothing about the next gesture.
    if state == .idle && Self.modBit(vk).isEmpty && !isTriggerVK(vk) && held() { foreignKey = true }

    if !suspended && vk == config.toggle.vk && mods() == config.toggle.mods {
      out.swallow = true
      swallowKeyUps.insert(vk)
      if !isRepeat {
        if enabled { cancelGesture(&out) }
        enabled.toggle()
        out.emits.append(.toggled(enabled))
      }
      return
    }
    if active {
      if vk == VK.escape && (state == .pending || state == .wheel) {
        out.swallow = true
        swallowKeyUps.insert(vk)
        cancelGesture(&out)
        return
      }
      // A custom-key trigger would type: keep it from the OS.
      if case .key(let k) = config.trigger, vk == k {
        out.swallow = true
        swallowKeyUps.insert(vk)
        return
      }
    }
    // This down passes through, so any pending up-swallow for the key is stale: drop it.
    swallowKeyUps.remove(vk)
  }

  private func onKeyUp(_ e: InputEvent, _ out: inout GestureOutput) {
    let vk = e.vk & 0xFF
    let heldBefore = held()
    keyDown[Int(vk)] = false
    if !held() { foreignKey = false }
    let triggerReleased = heldBefore && !held() && isTriggerVK(vk)

    if swallowKeyUps.remove(vk) != nil { out.swallow = true }
    guard triggerReleased else { return }
    if state == .pending {
      if config.clickPing {
        out.emits.append(.click(GesturePoint(px, py)))
        state = .swallowUp
      } else {
        // Plain click: re-press now; the real button-up will pass through.
        out.replays.append(.buttonDown(dragButton))
        state = .idle
      }
    } else if state == .wheel {
      out.emits.append(.cancel)
      state = .swallowUp
    }
  }

  private func onMouseDown(_ e: InputEvent, _ out: inout GestureOutput) {
    if state == .swallowUp && e.button == dragButton { state = .idle }  // the matching up was lost
    // A new right-down means the previous right-up never arrived: don't swallow this one's.
    if e.button == .right { swallowRightUp = false }
    guard active else { return }
    if (state == .pending || state == .wheel) && e.button == .right {
      out.swallow = true
      swallowRightUp = true
      cancelGesture(&out)
      return
    }
    guard state == .idle, !foreignKey, startsGesture(e.button) else { return }
    // Probed only when a gesture would actually start, so plain clicks never pay for the check.
    if config.gameCheck, let probe = fullscreenProbe, probe(e.x, e.y) { return }
    out.swallow = true
    state = .pending
    dragButton = e.button
    px = e.x
    py = e.y
  }

  private func onMouseUp(_ e: InputEvent, _ out: inout GestureOutput) {
    if e.button == .right && swallowRightUp {
      swallowRightUp = false
      out.swallow = true
      return
    }
    guard state != .idle, e.button == dragButton else { return }
    out.swallow = true
    if state == .pending {
      if config.clickPing {
        out.emits.append(.click(GesturePoint(px, py)))
      } else {
        out.replays.append(.buttonDown(dragButton))
        out.replays.append(.buttonUp(dragButton))
      }
    } else if state == .wheel {
      out.emits.append(.wheelRelease(GesturePoint(e.x, e.y)))
    }
    state = .idle
  }

  private func onMouseMove(_ e: InputEvent, _ out: inout GestureOutput) {
    if state == .pending {
      let dx = Double(e.x - px), dy = Double(e.y - py)
      if (dx * dx + dy * dy).squareRoot() > Double(config.dragThresholdPx) {
        state = .wheel
        out.emits.append(.wheelOpen(GesturePoint(px, py)))
        out.emits.append(.wheelMove(GesturePoint(e.x, e.y)))
      }
    } else if state == .wheel {
      out.emits.append(.wheelMove(GesturePoint(e.x, e.y)))
    }
  }

  // MARK: Helpers

  private var active: Bool { enabled && !suspended }

  private func cancelGesture(_ out: inout GestureOutput) {
    if state == .pending || state == .wheel {
      out.emits.append(.cancel)
      state = .swallowUp
    }
  }

  private static func modBit(_ vk: UInt32) -> Mods {
    switch vk {
    case VK.control, VK.lControl, VK.rControl: return .control
    case VK.option, VK.lOption, VK.rOption: return .option
    case VK.shift, VK.lShift, VK.rShift: return .shift
    case VK.lCommand, VK.rCommand: return .command
    default: return []
    }
  }

  private func mods() -> Mods {
    var m: Mods = []
    for vk in 0..<256 where keyDown[vk] { m.formUnion(Self.modBit(UInt32(vk))) }
    return m
  }

  /// Keyboard triggers only: a mouse trigger is never "held".
  private func held() -> Bool {
    switch config.trigger {
    case .option: return mods().contains(.option)
    case .control: return mods().contains(.control)
    case .shift: return mods().contains(.shift)
    case .command: return mods().contains(.command)
    case .key(let vk): return keyDown[Int(vk & 0xFF)]
    case .mouse4, .mouse5: return false
    }
  }

  private func isTriggerVK(_ vk: UInt32) -> Bool {
    switch config.trigger {
    case .option: return Self.modBit(vk) == .option
    case .control: return Self.modBit(vk) == .control
    case .shift: return Self.modBit(vk) == .shift
    case .command: return Self.modBit(vk) == .command
    case .key(let k): return vk == k
    case .mouse4, .mouse5: return false
    }
  }

  private func triggerButton() -> MouseButton {
    switch config.trigger {
    case .mouse4: return .x1
    case .mouse5: return .x2
    default: return .left
    }
  }

  /// A press starts a gesture: the side button of a mouse trigger, or the left button while the key is held.
  private func startsGesture(_ button: MouseButton) -> Bool {
    guard button == triggerButton() else { return false }
    switch config.trigger {
    case .mouse4, .mouse5: return true
    default: return held()
    }
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过（GestureMachineTests 35 个用例）。

- [ ] **Step 6: Commit**

```bash
git add Core/Input/GestureTypes.swift Core/Input/GestureMachine.swift Tests/GestureMachineTests.swift
git commit -m "Port gesture state machine from lolPing decision.cpp

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 扇区几何与坐标换算

**Files:**
- Create: `Core/Geometry/WheelGeometry.swift`, `Core/Geometry/ScreenMath.swift`, `Tests/WheelGeometryTests.swift`, `Tests/ScreenMathTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/WheelGeometryTests.swift`：

```swift
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
```

`Tests/ScreenMathTests.swift`：

```swift
import CoreGraphics
import Testing
@testable import PingCore

@Suite struct ScreenMathTests {
  // Primary screen 1440×900 at AppKit origin (0,0); a second screen 1920×1080 to its right, bottoms aligned.
  let primaryHeight: CGFloat = 900
  let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

  @Test func globalToAppKit() {
    #expect(ScreenMath.appKitPoint(fromGlobal: CGPoint(x: 10, y: 20), primaryHeight: primaryHeight) == CGPoint(x: 10, y: 880))
  }

  @Test func appKitToGlobal() {
    #expect(ScreenMath.globalPoint(fromAppKit: CGPoint(x: 10, y: 880), primaryHeight: primaryHeight) == CGPoint(x: 10, y: 20))
  }

  @Test func localPointInSecondScreen() {
    // Global (1500, 100): 100 pt below the top of the second screen (whose top is at global y = 900 - 1080 = -180).
    let local = ScreenMath.localPoint(fromGlobal: CGPoint(x: 1500, y: 100), screenFrame: second, primaryHeight: primaryHeight)
    #expect(local == CGPoint(x: 60, y: 800))
  }

  @Test func globalRectOfScreen() {
    #expect(ScreenMath.globalRect(ofScreenFrame: second, primaryHeight: primaryHeight) == CGRect(x: 1440, y: -180, width: 1920, height: 1080))
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'WheelGeometry' in scope`。

- [ ] **Step 3: 实现**

`Core/Geometry/WheelGeometry.swift`：

```swift
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
```

`Core/Geometry/ScreenMath.swift`：

```swift
import CoreGraphics

/// Global coordinates (CGEvent, CGWindowList): origin at the primary screen's top-left, y down.
/// AppKit coordinates (NSScreen, NSWindow): origin at the primary screen's bottom-left, y up.
public enum ScreenMath {
  public static func appKitPoint(fromGlobal p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: p.x, y: primaryHeight - p.y)
  }

  public static func globalPoint(fromAppKit p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: p.x, y: primaryHeight - p.y)
  }

  /// A global point in the coordinate space of a window covering `screenFrame` (AppKit, y up).
  public static func localPoint(fromGlobal p: CGPoint, screenFrame: CGRect, primaryHeight: CGFloat) -> CGPoint {
    let a = appKitPoint(fromGlobal: p, primaryHeight: primaryHeight)
    return CGPoint(x: a.x - screenFrame.minX, y: a.y - screenFrame.minY)
  }

  public static func globalRect(ofScreenFrame f: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Core/Geometry Tests/WheelGeometryTests.swift Tests/ScreenMathTests.swift
git commit -m "Add slice picking and screen coordinate conversion

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 标记目录与风格

**Files:**
- Create: `Core/Model/PingCatalog.swift`, `Tests/PingCatalogTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/PingCatalogTests.swift`：

```swift
import Foundation
import Testing
@testable import PingCore

@Suite struct PingCatalogTests {
  @Test func classicWheelIsFixedCompass() {
    #expect(PingCatalog.wheel(style: .classic, modernWheel: PingCatalog.defaultModernWheel)
      == [.danger, .omw, .assist, .missing])
    #expect(WheelStyle.classic.slots == 4)
    #expect(PingCatalog.clickPing(style: .classic, modernClickPing: .bait) == .generic)
  }

  @Test func modernWheelFollowsSettings() {
    let custom: [PingID] = [.bait, .push, .omw, .allin, .assist, .needvision, .missing, .enemyvision]
    #expect(PingCatalog.wheel(style: .modern, modernWheel: custom) == custom)
    #expect(WheelStyle.modern.slots == 8)
    #expect(PingCatalog.clickPing(style: .modern, modernClickPing: .bait) == .bait)
  }

  @Test func everyWheelPingHasADefinition() {
    for style in WheelStyle.allCases {
      let ids = PingCatalog.wheel(style: style, modernWheel: PingCatalog.defaultModernWheel)
        + [PingCatalog.clickPing(style: style, modernClickPing: .generic)]
      for id in ids { #expect(PingCatalog.def(id, style: style) != nil, "\(style) \(id)") }
    }
    for id in PingID.allCases { #expect(PingCatalog.def(id, style: .modern) != nil) }
  }

  @Test func classicDefinitions() {
    let missing = PingCatalog.def(.missing, style: .classic)!
    #expect(missing.art == ["ping-mia_02"])
    #expect(missing.base == ["ping-mia-base", "ping-mia-base-outer"])
    #expect(missing.sound == "MIA")
    #expect(missing.color == 0xB2A323)
    #expect(missing.wheelIcon == .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)))
    #expect(PingCatalog.def(.danger, style: .classic)?.sound == "GetBack")
    #expect(PingCatalog.def(.push, style: .classic) == nil)
  }

  @Test func allSoundsListsEachOnce() {
    let s = PingCatalog.allSounds
    #expect(Set(s).count == s.count)
    #expect(s.count == 13)
    #expect(s.contains("GetBack") && s.contains("button") && s.contains("SRP_12"))
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'PingCatalog' in scope`。

- [ ] **Step 3: 实现**

`Core/Model/PingCatalog.swift`：

```swift
public enum PingID: String, Codable, CaseIterable, Sendable {
  case danger, push, omw, allin, assist, needvision, missing, enemyvision, generic, bait, visioncleared
}

public enum WheelStyle: String, Codable, CaseIterable, Sendable {
  /// League before patch 12.22 (2022): four fixed pings.
  case classic
  /// League's current eight-slice wheel, editable.
  case modern

  public var slots: Int { self == .classic ? 4 : 8 }
}

/// A sprite in the classic wheel atlas (contextwheel_atlas.png), in atlas pixels, origin top-left.
public struct AtlasRect: Equatable, Sendable {
  public let x: Int, y: Int, w: Int, h: Int
  public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public enum WheelIcon: Equatable, Sendable {
  case texture(String)
  case atlas(AtlasRect)
}

public struct PingDef: Equatable, Sendable {
  public let id: PingID
  public let wheelIcon: WheelIcon
  /// Textures drawn at the ping location (file names without .png). Two entries = All In's clashing halves.
  public let art: [String]
  /// Classic only: white base textures tinted with `color`, drawn flat under the icon.
  public let base: [String]
  /// Sound file name without extension.
  public let sound: String
  /// 0xRRGGBB
  public let color: UInt32
}

public enum PingCatalog {
  public static let defaultModernWheel: [PingID] = [.danger, .push, .omw, .allin, .assist, .needvision, .missing, .enemyvision]
  public static let classicWheel: [PingID] = [.danger, .omw, .assist, .missing]
  public static let tickSound = "button"

  private static func modern(_ id: PingID, _ icon: String, _ art: [String], _ sound: String, _ color: UInt32) -> PingDef {
    PingDef(id: id, wheelIcon: .texture(icon), art: art, base: [], sound: sound, color: color)
  }

  /// From lolPing src/shared/pings.ts.
  private static let modernDefs: [PingID: PingDef] = Dictionary(uniqueKeysWithValues: [
    modern(.danger, "pingwheel_retreatrender", ["pingwheel_retreatrender"], "SRP_12", 0xFF3B55),
    modern(.push, "push", ["pingwheel_pushrender"], "SRP_9", 0x35D27A),
    modern(.omw, "omw", ["omw"], "OnMyWay", 0x2E8BFF),
    modern(.allin, "all_in", ["pingwheel_allin_render_01", "pingwheel_allin_render_02"], "SRP_4", 0xF2B320),
    modern(.assist, "assist_me", ["assist_me"], "ComeHere", 0x56D43C),
    modern(.needvision, "need_vision", ["need_vision"], "SRP_7", 0x56D43C),
    modern(.missing, "enemy_missing", ["enemy_missing"], "MIA", 0xF2C518),
    modern(.enemyvision, "enemy_vision", ["pingwheel_enemyvisionrender"], "AreaIsWarded", 0xFF3B55),
    modern(.generic, "generic_ping", ["pingwheel_basicpingrender"], "Base", 0x2E8BFF),
    modern(.bait, "pingwheel_baitrender", ["pingwheel_baitrender"], "SRP_11", 0xEFBC12),
    modern(.visioncleared, "vision_cleared", ["pingwheel_visionclearedrender"], "SRP_6", 0x2B80FF),
  ].map { ($0.id, $0) })

  /// Patch 12.21 assets (CommunityDragon). Colours are the peaks of each *-base-color.png ramp.
  private static let classicDefs: [PingID: PingDef] = Dictionary(uniqueKeysWithValues: [
    PingDef(id: .danger, wheelIcon: .atlas(AtlasRect(x: 467, y: 70, w: 26, h: 52)),
            art: ["ping-danger"], base: ["ping-danger-base"], sound: "GetBack", color: 0xFF0000),
    PingDef(id: .omw, wheelIcon: .atlas(AtlasRect(x: 389, y: 70, w: 54, h: 52)),
            art: ["ping-omw_02"], base: ["ping-omw-base"], sound: "OnMyWay", color: 0x26AA99),
    PingDef(id: .assist, wheelIcon: .atlas(AtlasRect(x: 464, y: 6, w: 46, h: 52)),
            art: ["ping-comehere_02"], base: ["ping-comehere-base"], sound: "ComeHere", color: 0x189CDB),
    PingDef(id: .missing, wheelIcon: .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)),
            art: ["ping-mia_02"], base: ["ping-mia-base", "ping-mia-base-outer"], sound: "MIA", color: 0xB2A323),
    PingDef(id: .generic, wheelIcon: .atlas(AtlasRect(x: 400, y: 6, w: 32, h: 52)),
            art: ["sr_pings_blue_02"], base: ["ping-command-base"], sound: "Base", color: 0x3179C6),
  ].map { ($0.id, $0) })

  public static func def(_ id: PingID, style: WheelStyle) -> PingDef? {
    style == .classic ? classicDefs[id] : modernDefs[id]
  }

  public static func wheel(style: WheelStyle, modernWheel: [PingID]) -> [PingID] {
    style == .classic ? classicWheel : modernWheel
  }

  public static func clickPing(style: WheelStyle, modernClickPing: PingID) -> PingID {
    style == .classic ? .generic : modernClickPing
  }

  /// Every sound either style plays, each once.
  public static var allSounds: [String] {
    var seen = Set<String>(), out: [String] = []
    for d in Array(modernDefs.values) + Array(classicDefs.values) where seen.insert(d.sound).inserted { out.append(d.sound) }
    if seen.insert(tickSound).inserted { out.append(tickSound) }
    return out
  }

  /// Every texture either style draws (file names without .png), including the classic atlas.
  public static var allTextures: [String] {
    var seen = Set<String>(["contextwheel_atlas"]), out = ["contextwheel_atlas"]
    for d in Array(modernDefs.values) + Array(classicDefs.values) {
      var names = d.art + d.base
      if case .texture(let t) = d.wheelIcon { names.append(t) }
      for n in names where seen.insert(n).inserted { out.append(n) }
    }
    return out
  }
}
```

（经典「普通标记」不出现在轮盘上，`wheelIcon` 不会被用到，这里复用 `?` 的切片只为满足类型。）

- [ ] **Step 4: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Core/Model/PingCatalog.swift Tests/PingCatalogTests.swift
git commit -m "Add ping catalog for classic and modern styles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 设置模型与持久化

**Files:**
- Create: `Core/Model/Settings.swift`, `Tests/SettingsTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/SettingsTests.swift`：

```swift
import Foundation
import Testing
@testable import PingCore

@Suite struct SettingsTests {
  private func decode(_ json: String) -> Settings {
    Settings.decodeLeniently(Data(json.utf8))
  }

  @Test func defaults() {
    let s = Settings()
    #expect(s.style == .classic)
    #expect(s.trigger == .option)
    #expect(s.dragThresholdPx == 8)
    #expect(s.wheel == PingCatalog.defaultModernWheel)
    #expect(s.toggleHotkey == .defaultToggle)
    #expect(s.pingSizePx == 110 && s.pingDurationS == 3.2 && s.volume == 70)
    #expect(s.gameCheck && s.tickSound && s.enabledOnStart && !s.clickPing && !s.muted)
  }

  @Test func roundTrip() throws {
    var s = Settings()
    s.style = .modern
    s.trigger = .key(0x56)
    s.volume = 40
    let back = Settings.decodeLeniently(try JSONEncoder().encode(s))
    #expect(back == s)
  }

  @Test func missingFieldsFallBack() {
    let s = decode(#"{"volume": 30}"#)
    #expect(s.volume == 30)
    #expect(s.style == .classic)
    #expect(s.pingSizePx == 110)
  }

  @Test func badFieldsFallBackIndividually() {
    let s = decode(#"{"volume": "loud", "style": "retro", "trigger": "hyper", "pingSizePx": 150}"#)
    #expect(s.volume == 70)
    #expect(s.style == .classic)
    #expect(s.trigger == .option)
    #expect(s.pingSizePx == 150)
  }

  @Test func outOfRangeIsClamped() {
    let s = decode(#"{"volume": 900, "dragThresholdPx": 0, "pingSizePx": 1000, "pingDurationS": 0.1}"#)
    #expect(s.volume == 100)
    #expect(s.dragThresholdPx == 2)
    #expect(s.pingSizePx == 220)
    #expect(s.pingDurationS == 1)
  }

  @Test func invalidWheelFallsBack() {
    #expect(decode(#"{"wheel": ["push"]}"#).wheel == PingCatalog.defaultModernWheel)
    #expect(decode(#"{"wheel": ["push","push","omw","allin","assist","needvision","missing","enemyvision"]}"#).wheel
      == PingCatalog.defaultModernWheel)
    let ok = #"{"wheel": ["bait","push","omw","allin","assist","needvision","missing","enemyvision"]}"#
    #expect(decode(ok).wheel.first == .bait)
  }

  @Test func hotkeyNeedsAPrimaryModifier() {
    #expect(decode(#"{"toggleHotkey": {"mods": 4, "vk": 80}}"#).toggleHotkey == .defaultToggle)  // Shift only
    #expect(decode(#"{"toggleHotkey": {"mods": 8, "vk": 80}}"#).toggleHotkey == Hotkey(mods: .command, vk: 80))
  }

  @Test func customTriggerCannotBeTheHotkeyKey() {
    let s = decode(#"{"trigger": "key:80"}"#)  // P, the default ⌃⌥P key
    #expect(s.trigger == .option)
  }

  @Test func gestureConfigMirrorsSettings() {
    var s = Settings()
    s.clickPing = true
    s.trigger = .mouse4
    let c = s.gestureConfig(enabled: false)
    #expect(c.clickPing && c.trigger == .mouse4 && c.gameCheck && !c.enabled && c.dragThresholdPx == 8)
  }

  @Test func storePersists() {
    let defaults = UserDefaults(suiteName: "ping-signals-tests-\(UUID().uuidString)")!
    let store = SettingsStore(defaults: defaults)
    #expect(store.load() == Settings())
    var s = Settings()
    s.style = .modern
    store.save(s)
    #expect(SettingsStore(defaults: defaults).load().style == .modern)
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'Settings' in scope`。

- [ ] **Step 3: 实现**

`Core/Model/Settings.swift`：

```swift
import Foundation

public enum LanguagePref: String, Codable, CaseIterable, Sendable { case auto, zhHans, en }

public struct Settings: Codable, Equatable, Sendable {
  public var version = 1
  public var enabledOnStart = true
  public var style: WheelStyle = .classic
  public var trigger: Trigger = .option
  public var dragThresholdPx = 8
  public var clickPing = false
  /// Modern only; classic always places the generic ping.
  public var clickPingID: PingID = .generic
  public var gameCheck = true
  /// Modern only.
  public var wheel: [PingID] = PingCatalog.defaultModernWheel
  public var toggleHotkey: Hotkey = .defaultToggle
  public var pingSizePx = 110
  public var pingDurationS = 3.2
  public var volume = 70
  public var muted = false
  public var tickSound = true
  public var launchAtLogin = false
  public var language: LanguagePref = .auto
  public var autoUpdateCheck = true

  public static let dragRange = 2...40
  public static let sizeRange = 60...220
  public static let durationRange = 1.0...8.0
  public static let volumeRange = 0...100

  public init() {}

  public func gestureConfig(enabled: Bool) -> GestureConfig {
    var c = GestureConfig()
    c.trigger = trigger
    c.clickPing = clickPing
    c.gameCheck = gameCheck
    c.dragThresholdPx = dragThresholdPx
    c.toggle = toggleHotkey
    c.enabled = enabled
    return c
  }

  /// Decodes field by field: a missing or invalid field takes its default, numbers are clamped,
  /// so an old or hand-edited file never loses the rest of the settings.
  public static func decodeLeniently(_ data: Data) -> Settings {
    var s = Settings()
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return s }
    func field<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
      guard let v = obj[key], let d = try? JSONSerialization.data(withJSONObject: [v]) else { return nil }
      return (try? JSONDecoder().decode([T].self, from: d))?.first
    }
    func clamp<T: Comparable>(_ v: T, _ r: ClosedRange<T>) -> T { min(max(v, r.lowerBound), r.upperBound) }

    if let v = field("enabledOnStart", Bool.self) { s.enabledOnStart = v }
    if let v = field("style", WheelStyle.self) { s.style = v }
    if let v = field("trigger", Trigger.self) { s.trigger = v }
    if let v = field("dragThresholdPx", Int.self) { s.dragThresholdPx = clamp(v, dragRange) }
    if let v = field("clickPing", Bool.self) { s.clickPing = v }
    if let v = field("clickPingID", PingID.self) { s.clickPingID = v }
    if let v = field("gameCheck", Bool.self) { s.gameCheck = v }
    if let v = field("wheel", [PingID].self), v.count == 8, Set(v).count == 8 { s.wheel = v }
    if let v = field("toggleHotkey", Hotkey.self), !v.mods.isDisjoint(with: [.control, .option, .command]) {
      s.toggleHotkey = v
    }
    if let v = field("pingSizePx", Int.self) { s.pingSizePx = clamp(v, sizeRange) }
    if let v = field("pingDurationS", Double.self) { s.pingDurationS = clamp(v, durationRange) }
    if let v = field("volume", Int.self) { s.volume = clamp(v, volumeRange) }
    if let v = field("muted", Bool.self) { s.muted = v }
    if let v = field("tickSound", Bool.self) { s.tickSound = v }
    if let v = field("launchAtLogin", Bool.self) { s.launchAtLogin = v }
    if let v = field("language", LanguagePref.self) { s.language = v }
    if let v = field("autoUpdateCheck", Bool.self) { s.autoUpdateCheck = v }
    // A custom trigger key can't be the pause shortcut's key.
    if case .key(let vk) = s.trigger, vk == s.toggleHotkey.vk { s.trigger = .option }
    return s
  }
}

public final class SettingsStore {
  private let defaults: UserDefaults
  private let key = "settings.v1"

  public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  public func load() -> Settings {
    guard let data = defaults.data(forKey: key) else { return Settings() }
    return Settings.decodeLeniently(data)
  }

  public func save(_ s: Settings) {
    if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Core/Model/Settings.swift Tests/SettingsTests.swift
git commit -m "Add settings model with lenient decoding and store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 信号总线

**Files:**
- Create: `Core/Signals/SignalBus.swift`, `Tests/SignalBusTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/SignalBusTests.swift`：

```swift
import Foundation
import Testing
@testable import PingCore

@MainActor
private final class Recorder: SignalHandler {
  let name: String
  var log: [String]
  init(_ name: String, log: [String] = []) { self.name = name; self.log = log }
  func handle(_ signal: PingSignal) { log.append("\(name):\(signal.ping.rawValue)") }
}

@MainActor
@Suite struct SignalBusTests {
  private func signal(_ id: PingID) -> PingSignal {
    PingSignal(ping: id, style: .classic, point: GesturePoint(10, 20), frontApp: "com.apple.Safari",
               time: Date(timeIntervalSince1970: 0), source: .wheel)
  }

  @Test func deliversToHandlersInOrder() {
    let bus = SignalBus()
    let shared = Recorder("shared")
    let a = Recorder("a"), b = Recorder("b")
    bus.register(a)
    bus.register(b)
    bus.register(shared)
    bus.emit(signal(.missing))
    bus.emit(signal(.danger))
    #expect(a.log == ["a:missing", "a:danger"])
    #expect(b.log == ["b:missing", "b:danger"])
    #expect(bus.handlerCount == 3)
  }

  @Test func emptyBusIsFine() {
    SignalBus().emit(signal(.omw))
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 跑测试 → Expected: 编译失败，`cannot find 'SignalBus' in scope`。

- [ ] **Step 3: 实现**

`Core/Signals/SignalBus.swift`：

```swift
import Foundation

/// One placed ping. v1 only animates it; later handlers give each ping a meaning (e.g. "?" logs a question).
public struct PingSignal: Equatable, Sendable {
  public enum Source: Equatable, Sendable { case wheel, click }
  public let ping: PingID
  public let style: WheelStyle
  /// Global coordinates (primary screen's top-left origin, y down).
  public let point: GesturePoint
  /// Bundle identifier of the frontmost app when the ping was placed.
  public let frontApp: String?
  public let time: Date
  public let source: Source

  public init(ping: PingID, style: WheelStyle, point: GesturePoint, frontApp: String?, time: Date, source: Source) {
    self.ping = ping; self.style = style; self.point = point; self.frontApp = frontApp; self.time = time; self.source = source
  }
}

/// Handles a signal without throwing: a failing handler must not stop the others.
@MainActor
public protocol SignalHandler: AnyObject {
  func handle(_ signal: PingSignal)
}

@MainActor
public final class SignalBus {
  private var handlers: [SignalHandler] = []

  public init() {}

  public var handlerCount: Int { handlers.count }

  public func register(_ handler: SignalHandler) { handlers.append(handler) }

  /// Calls every handler in registration order, synchronously.
  public func emit(_ signal: PingSignal) {
    for h in handlers { h.handle(signal) }
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 跑测试 → Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Core/Signals Tests/SignalBusTests.swift
git commit -m "Add signal bus for ping actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 导入素材

**Files:**
- Create: `scripts/import-assets.sh`
- Create (generated, committed): `App/Resources/Textures/*.png`, `App/Resources/Sounds/*.m4a`

- [ ] **Step 1: 写导入脚本**

`scripts/import-assets.sh`：

```bash
#!/bin/bash
# Copies the textures and sounds the app uses into App/Resources.
# Modern assets come from the lolPing reference checkout, classic ones from reference/classic-12.21.
# Sounds are converted to AAC .m4a, all 44.1 kHz stereo so one AVAudioEngine format plays them all.
set -euo pipefail
cd "$(dirname "$0")/.."
LOLPING="${LOLPING:-$HOME/sandbox/lolping-fork/assets}"
CLASSIC=reference/classic-12.21/world
TEX=App/Resources/Textures
SND=App/Resources/Sounds
rm -rf "$TEX" "$SND"
mkdir -p "$TEX" "$SND"

TEXTURES=(contextwheel_atlas
  pingwheel_retreatrender push pingwheel_pushrender omw all_in pingwheel_allin_render_01 pingwheel_allin_render_02
  assist_me need_vision enemy_missing enemy_vision pingwheel_enemyvisionrender generic_ping pingwheel_basicpingrender
  pingwheel_baitrender vision_cleared pingwheel_visionclearedrender
  ping-danger ping-danger-base ping-omw_02 ping-omw-base ping-comehere_02 ping-comehere-base
  ping-mia_02 ping-mia-base ping-mia-base-outer sr_pings_blue_02 ping-command-base)
for t in "${TEXTURES[@]}"; do
  if [ -f "$CLASSIC/$t.png" ]; then cp "$CLASSIC/$t.png" "$TEX/"; else cp "$LOLPING/textures/$t.png" "$TEX/"; fi
done

SOUNDS=(SRP_12 SRP_9 OnMyWay SRP_4 ComeHere SRP_7 MIA AreaIsWarded Base SRP_11 SRP_6 GetBack button)
for s in "${SOUNDS[@]}"; do
  afconvert -f m4af -d aac@44100 -c 2 -b 128000 "$LOLPING/sounds/$s.wav" "$SND/$s.m4a"
done
echo "textures: $(ls "$TEX" | wc -l | tr -d ' ')  sounds: $(ls "$SND" | wc -l | tr -d ' ')"
du -sh "$TEX" "$SND"
```

- [ ] **Step 2: 写一个测试，保证脚本清单与目录一致**

在 `Tests/PingCatalogTests.swift` 的 `PingCatalogTests` 里追加（直接检查仓库里的资源目录，路径相对于测试源文件）：

```swift
  @Test func resourcesMatchCatalog() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let fm = FileManager.default
    let textures = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("App/Resources/Textures").path)
    let sounds = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("App/Resources/Sounds").path)
    #expect(Set(textures) == Set(PingCatalog.allTextures.map { "\($0).png" }))
    #expect(Set(sounds) == Set(PingCatalog.allSounds.map { "\($0).m4a" }))
  }
```

- [ ] **Step 3: 跑测试确认失败**

Run: 跑测试 → Expected: `resourcesMatchCatalog` 失败（目录不存在）。

- [ ] **Step 4: 运行脚本**

Run: `chmod +x scripts/import-assets.sh && scripts/import-assets.sh`
Expected: `textures: 29  sounds: 13`，两个目录合计约 2 MB 以内。

- [ ] **Step 5: 重新生成工程并跑测试**

Run: `xcodegen generate &&` 跑测试 → Expected: 全部通过。资源会作为 `App` 目录下的文件自动进入应用包（XcodeGen 把 png / m4a 识别为资源）。
验证：编译应用后 `ls build/Build/Products/Debug/ping-signals.app/Contents/Resources | head` 能看到 `MIA.m4a`、`contextwheel_atlas.png`。

- [ ] **Step 6: Commit**

```bash
git add scripts/import-assets.sh App/Resources Tests/PingCatalogTests.swift
git commit -m "Import ping textures and AAC sounds

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 轮盘绘制工具与经典轮盘渲染 + 预览（**用户确认节点**）

轮盘画成三张图叠放：`under`（底）、`highlights[i]`（第 i 格高亮）、`over`（边框、图标、中心），外加 `centerHot`（死区内时显示）。打开轮盘后只切换图层可见性，不重绘。

**Files:**
- Create: `App/Overlay/Drawing.swift`, `App/Overlay/WheelArt.swift`, `App/Overlay/ClassicWheelRenderer.swift`
- Modify: `App/main.swift`

- [ ] **Step 1: 写绘制工具**

`App/Overlay/Drawing.swift`：

```swift
import AppKit
import CoreGraphics
import PingCore

/// Bitmap drawing in a y-down coordinate space (like SVG / the atlas), at a given pixel scale.
enum Drawing {
  /// Draws into a bitmap of `size` points × `scale`, origin at the top-left, y down.
  static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
    let w = Int((size.width * scale).rounded(.up)), h = Int((size.height * scale).rounded(.up))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
  }

  /// Draws `img` into `rect` of a y-down context without flipping it.
  static func draw(_ img: CGImage, in rect: CGRect, _ ctx: CGContext, alpha: CGFloat = 1) {
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
  }

  /// Draws `img` centred at `center` with its natural size × `scale`, rotated clockwise by `degrees`.
  static func draw(_ img: CGImage, centeredAt center: CGPoint, size: CGSize, degrees: CGFloat = 0, _ ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    draw(img, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height), ctx)
    ctx.restoreGState()
  }

  static func color(_ rgb: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
  }
}

/// Bundled textures, loaded once.
@MainActor
enum Textures {
  private static var cache: [String: CGImage] = [:]

  static func named(_ name: String) -> CGImage? {
    if let c = cache[name] { return c }
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    cache[name] = img
    return img
  }

  /// A sprite cut from the classic wheel atlas.
  static func atlas(_ r: AtlasRect) -> CGImage? {
    named("contextwheel_atlas")?.cropping(to: CGRect(x: r.x, y: r.y, width: r.w, height: r.h))
  }

  /// A white/grey texture recoloured with `rgb`, keeping its alpha and brightness.
  static func tinted(_ name: String, _ rgb: UInt32) -> CGImage? {
    let key = "\(name)#\(rgb)"
    if let c = cache[key] { return c }
    guard let src = named(name) else { return nil }
    let size = CGSize(width: src.width, height: src.height)
    let out = Drawing.image(size: size, scale: 1) { ctx in
      let rect = CGRect(origin: .zero, size: size)
      Drawing.draw(src, in: rect, ctx)
      ctx.setBlendMode(.multiply)
      ctx.setFillColor(Drawing.color(rgb))
      ctx.fill(rect)
      ctx.setBlendMode(.destinationIn)
      Drawing.draw(src, in: rect, ctx)
    }
    cache[key] = out
    return out
  }
}
```

- [ ] **Step 2: 写 WheelArt**

`App/Overlay/WheelArt.swift`：

```swift
import AppKit
import CoreGraphics
import PingCore

/// A rendered wheel: stacked images, all `size` points, centred on the wheel origin.
struct WheelArt {
  let size: CGSize
  let scale: CGFloat
  let under: CGImage
  let highlights: [CGImage]
  let over: CGImage
  /// Shown while the pointer is in the dead zone.
  let centerHot: CGImage?
  /// In points, from the wheel centre.
  let deadZone: CGFloat

  var slots: Int { highlights.count }

  /// Composites a still frame (for previews): `hot` = highlighted slice, nil = dead zone.
  func composite(hot: Int?) -> CGImage {
    Drawing.image(size: size, scale: scale) { ctx in
      let r = CGRect(origin: .zero, size: size)
      Drawing.draw(under, in: r, ctx)
      if let h = hot { Drawing.draw(highlights[h], in: r, ctx) }
      Drawing.draw(over, in: r, ctx)
      if hot == nil, let c = centerHot { Drawing.draw(c, in: r, ctx) }
    }
  }

  /// Writes the idle frame and one frame per highlighted slice, side by side, as a PNG.
  func writePreview(to url: URL) throws {
    let frames = [composite(hot: nil)] + (0..<slots).map { composite(hot: $0) }
    let sheet = Drawing.image(size: CGSize(width: size.width * CGFloat(frames.count), height: size.height), scale: scale) { ctx in
      ctx.setFillColor(Drawing.color(0x3A4A42))
      ctx.fill(CGRect(x: 0, y: 0, width: size.width * CGFloat(frames.count), height: size.height))
      for (i, f) in frames.enumerated() {
        Drawing.draw(f, in: CGRect(x: size.width * CGFloat(i), y: 0, width: size.width, height: size.height), ctx)
      }
    }
    let rep = NSBitmapImageRep(cgImage: sheet)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
  }
}
```

- [ ] **Step 3: 写经典轮盘渲染**

按 `reference/classic_wheel_mockup.py` 的拼装方式（参考图 `reference/classic-wheel-target.png`）。图集坐标系：轮盘半径 R = 142 atlas px，画布 320×320 atlas px，中心 (160,160)；`classicScale` 把 atlas px 换成 point。

`App/Overlay/ClassicWheelRenderer.swift`：

```swift
import CoreGraphics
import PingCore

/// The pre-12.22 four-ping wheel, assembled from contextwheel_atlas.png sprites.
@MainActor
enum ClassicWheelRenderer {
  /// Points per atlas pixel. 1.25 → a 355 pt wheel.
  static let classicScale: CGFloat = 1.25
  private static let R: CGFloat = 142, C: CGFloat = 160, canvas: CGFloat = 320

  private static let quarter = AtlasRect(x: 1, y: 1, w: 142, h: 142)          // top-left quadrant of the frame
  private static let wedgeTop = AtlasRect(x: 169, y: 145, w: 166, h: 115)     // highlighted north wedge
  private static let wedgeSide = AtlasRect(x: 172, y: 263, w: 115, h: 166)    // highlighted west wedge
  private static let disc = AtlasRect(x: 373, y: 228, w: 135, h: 135)
  private static let shadow = AtlasRect(x: 371, y: 371, w: 140, h: 140)
  private static let center = AtlasRect(x: 0, y: 426, w: 86, h: 86)
  private static let cancel = AtlasRect(x: 96, y: 448, w: 60, h: 60)
  private static let cancelHot = AtlasRect(x: 166, y: 448, w: 60, h: 60)

  static func render(wheel: [PingID], pixelScale: CGFloat) -> WheelArt {
    let s = classicScale
    let size = CGSize(width: canvas * s, height: canvas * s)
    let px = s * pixelScale
    let atlasSize = CGSize(width: canvas, height: canvas)
    func sprite(_ r: AtlasRect) -> CGImage { Textures.atlas(r)! }
    func natural(_ r: AtlasRect) -> CGSize { CGSize(width: r.w, height: r.h) }
    // Every layer is drawn in atlas pixels and scaled by `s` via the bitmap scale.
    func layer(_ draw: @escaping (CGContext) -> Void) -> CGImage {
      Drawing.image(size: atlasSize, scale: px, draw)
    }

    let under = layer { ctx in
      Drawing.draw(sprite(shadow), centeredAt: CGPoint(x: C, y: C + 3), size: CGSize(width: 2 * R + 8, height: 2 * R + 8), ctx)
      let discRect = CGRect(x: C - R, y: C - R, width: 2 * R, height: 2 * R)
      Drawing.draw(sprite(disc), in: discRect, ctx)
      ctx.saveGState()
      ctx.addEllipse(in: discRect)
      ctx.clip()
      ctx.setFillColor(CGColor(gray: 0, alpha: 0.72))   // darkens the grey disc like the game's dark base
      ctx.fill(discRect)
      ctx.restoreGState()
    }

    // North and west wedges; south and east are the same sprites turned 180° about the wheel centre.
    let highlights: [CGImage] = (0..<4).map { i in
      layer { ctx in
        ctx.translateBy(x: C, y: C)
        ctx.rotate(by: i >= 2 ? .pi : 0)
        ctx.translateBy(x: -C, y: -C)
        if i % 2 == 0 {
          let sz = natural(wedgeTop)
          Drawing.draw(sprite(wedgeTop), centeredAt: CGPoint(x: C, y: C - R + sz.height / 2 + 4), size: sz, ctx)
        } else {
          let sz = natural(wedgeSide)
          Drawing.draw(sprite(wedgeSide), centeredAt: CGPoint(x: C - R + sz.width / 2 + 4, y: C), size: sz, ctx)
        }
      }
    }
    // Slice order is N, E, S, W: highlights above were built as N, W, S, E — reorder.
    let ordered = [highlights[0], highlights[3], highlights[2], highlights[1]]

    let over = layer { ctx in
      for k in 0..<4 {
        ctx.saveGState()
        ctx.translateBy(x: C, y: C)
        ctx.rotate(by: CGFloat(k) * .pi / 2)                  // clockwise in y-down space
        ctx.translateBy(x: -C, y: -C)
        Drawing.draw(sprite(quarter), in: CGRect(x: C - R, y: C - R, width: R, height: R), ctx)
        ctx.restoreGState()
      }
      Drawing.draw(sprite(center), centeredAt: CGPoint(x: C, y: C), size: natural(center), ctx)
      Drawing.draw(sprite(cancel), centeredAt: CGPoint(x: C, y: C), size: natural(cancel), ctx)
      let dirs: [CGPoint] = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]
      for (i, id) in wheel.enumerated() {
        guard let def = PingCatalog.def(id, style: .classic), case .atlas(let r) = def.wheelIcon else { continue }
        let p = CGPoint(x: C + dirs[i].x * R * 0.62, y: C + dirs[i].y * R * 0.62)
        Drawing.draw(sprite(r), centeredAt: p, size: natural(r), ctx)
      }
    }

    let hot = layer { ctx in
      Drawing.draw(sprite(cancelHot), centeredAt: CGPoint(x: C, y: C), size: natural(cancelHot), ctx)
    }

    return WheelArt(size: size, scale: pixelScale, under: under, highlights: ordered, over: over,
                    centerHot: hot, deadZone: CGFloat(center.w) / 2 * s)
  }
}
```

注意：`Drawing.draw(_:in:)` 里绘制 quarter 时，quarter 图片本身就是左上象限（右下角 = 轮盘中心），旋转 k×90° 后依次得到右上、右下、左下。

- [ ] **Step 4: 在 main.swift 加预览模式**

把 `App/main.swift` 改为：

```swift
import AppKit
import PingCore

// `ping-signals --render-wheels <dir>` writes wheel previews as PNGs and exits.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-wheels"), i + 1 < args.count {
  let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  MainActor.assumeIsolated {
    let classic = ClassicWheelRenderer.render(wheel: PingCatalog.classicWheel, pixelScale: 2)
    try? classic.writePreview(to: dir.appendingPathComponent("classic.png"))
  }
  exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 5: 编译并导出预览**

Run: 编译应用，然后
`build/Build/Products/Debug/ping-signals.app/Contents/MacOS/ping-signals --render-wheels /tmp/ping-preview && open /tmp/ping-preview/classic.png`
Expected: 一张 5 帧横排图（常态 + 上、右、下、左各高亮一次），与 `reference/classic-wheel-target.png` 一致：上 `!`、右 绿箭头、下 蓝旗、左 `?`，中心 ✕，金色边框四段完整衔接。

- [ ] **Step 6: 🔶 用户确认节点**

把预览图给用户看，确认经典轮盘外观与大小（`classicScale`）。用户要求调整时只改 `ClassicWheelRenderer` 的常量 / 摆放并重新导出，直到确认。**确认前不进入 Task 12 的经典轮盘接入。**

- [ ] **Step 7: Commit**

```bash
git add App/Overlay/Drawing.swift App/Overlay/WheelArt.swift App/Overlay/ClassicWheelRenderer.swift App/main.swift
git commit -m "Render classic wheel from the 12.21 atlas, with PNG preview mode

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 新版轮盘渲染

复刻 `lolping-fork/src/renderer/overlay/wheel.ts` 的 SVG。尺寸常量来自 `src/shared/geometry.ts`。

**Files:**
- Create: `App/Overlay/ModernWheelRenderer.swift`
- Modify: `App/main.swift`

- [ ] **Step 1: 实现**

`App/Overlay/ModernWheelRenderer.swift`：

```swift
import AppKit
import CoreGraphics
import PingCore

/// League's current eight-slice wheel, drawn like lolPing's SVG (wheel.ts).
@MainActor
enum ModernWheelRenderer {
  static let innerR: CGFloat = 86, outerR: CGFloat = 188, extR: CGFloat = 288, iconR: CGFloat = 137, iconSize: CGFloat = 48
  private static let half = extR + 4

  private static func polar(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
    CGPoint(x: r * cos(deg * .pi / 180), y: r * sin(deg * .pi / 180))
  }

  /// Annular sector between radii r0 and r1, from angle a0 to a1 (degrees, clockwise from +x, y down).
  private static func sector(_ r0: CGFloat, _ r1: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.addArc(center: .zero, radius: r1, startAngle: a0 * .pi / 180, endAngle: a1 * .pi / 180, clockwise: false)
    p.addArc(center: .zero, radius: r0, startAngle: a1 * .pi / 180, endAngle: a0 * .pi / 180, clockwise: true)
    p.closeSubpath()
    return p
  }

  private static func radial(_ ctx: CGContext, clip: CGPath, center: CGPoint = .zero, radius: CGFloat,
                             stops: [(CGFloat, UInt32, CGFloat)], evenOdd: Bool = false) {
    let colors = stops.map { Drawing.color($0.1, alpha: $0.2) } as CFArray
    let locs = stops.map { $0.0 }
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locs)!
    ctx.saveGState()
    ctx.addPath(clip)
    if evenOdd { ctx.clip(using: .evenOdd) } else { ctx.clip() }
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()
  }

  static func render(wheel: [PingID], pixelScale: CGFloat) -> WheelArt {
    let size = CGSize(width: half * 2, height: half * 2)
    func layer(_ draw: @escaping (CGContext) -> Void) -> CGImage {
      Drawing.image(size: size, scale: pixelScale) { ctx in
        ctx.translateBy(x: half, y: half)
        draw(ctx)
      }
    }
    let mids = (0..<8).map { -90 + CGFloat($0) * 45 }

    let under = layer { ctx in
      for i in stride(from: 0, to: 8, by: 2) {
        radial(ctx, clip: sector(outerR, extR, mids[i] - 22.5, mids[i] + 22.5), radius: extR,
               stops: [(outerR / extR, 0x5C6066, 0.55), (1, 0x5C6066, 0)])
      }
      let ring = CGMutablePath()
      ring.addEllipse(in: CGRect(x: -outerR, y: -outerR, width: 2 * outerR, height: 2 * outerR))
      ring.addEllipse(in: CGRect(x: -innerR, y: -innerR, width: 2 * innerR, height: 2 * innerR))
      ctx.setAlpha(0.92)
      radial(ctx, clip: ring, radius: outerR, stops: [(innerR / outerR, 0x2A2D31, 1), (1, 0x4A4E54, 1)], evenOdd: true)
      ctx.setAlpha(1)
    }

    let highlights: [CGImage] = (0..<8).map { i in
      layer { ctx in
        let reach = i % 2 == 0 ? extR : outerR
        ctx.setAlpha(0.55)
        radial(ctx, clip: sector(innerR, reach, mids[i] - 22.5, mids[i] + 22.5), radius: extR,
               stops: [(innerR / extR, 0x8A8F96, 1), (outerR / extR, 0x9AA0A8, 1), (1, 0x9AA0A8, 0)])
      }
    }

    let over = layer { ctx in
      ctx.setStrokeColor(Drawing.color(0xA08A5C, alpha: 0.45))
      ctx.setLineWidth(1.2)
      for m in mids {
        ctx.move(to: polar(innerR, m - 22.5))
        ctx.addLine(to: polar(outerR, m - 22.5))
      }
      ctx.strokePath()
      for (i, id) in wheel.enumerated() {
        guard let def = PingCatalog.def(id, style: .modern), case .texture(let name) = def.wheelIcon,
              let img = Textures.named(name) else { continue }
        Drawing.draw(img, centeredAt: polar(iconR, mids[i]), size: CGSize(width: iconSize, height: iconSize), ctx)
      }
      ctx.setStrokeColor(Drawing.color(0x1A1A1A, alpha: 0.6))
      ctx.setLineWidth(6)
      ctx.strokeEllipse(in: CGRect(x: -innerR - 4, y: -innerR - 4, width: 2 * innerR + 8, height: 2 * innerR + 8))
      let core = CGPath(ellipseIn: CGRect(x: -innerR, y: -innerR, width: 2 * innerR, height: 2 * innerR), transform: nil)
      radial(ctx, clip: core, center: CGPoint(x: 0, y: -10), radius: innerR, stops: [(0, 0x2C5D60, 1), (1, 0x11292C, 1)])
      ctx.setStrokeColor(Drawing.color(0xC8AA6E))
      ctx.setLineWidth(3)
      ctx.addPath(core)
      ctx.strokePath()
      ctx.setStrokeColor(Drawing.color(0x8A7448, alpha: 0.6))
      ctx.setLineWidth(1)
      ctx.strokeEllipse(in: CGRect(x: -innerR + 7, y: -innerR + 7, width: 2 * innerR - 14, height: 2 * innerR - 14))
      if let hub = Textures.named("generic_ping") {
        Drawing.draw(hub, in: CGRect(x: -20, y: -58, width: 40, height: 40), ctx)
      }
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
      let label = String(localized: "wheel.cancel", defaultValue: "Cancel")
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.85, green: 0.78, blue: 0.6, alpha: 1),
      ]
      let w = (label as NSString).size(withAttributes: attrs).width
      (label as NSString).draw(at: CGPoint(x: -w / 2, y: -2), withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    }

    return WheelArt(size: size, scale: pixelScale, under: under, highlights: highlights, over: over,
                    centerHot: nil, deadZone: innerR)
  }
}
```

- [ ] **Step 2: 预览模式里加新版**

在 `App/main.swift` 的 `MainActor.assumeIsolated { ... }` 块里，`classic` 那两行之后追加：

```swift
    let modern = ModernWheelRenderer.render(wheel: PingCatalog.defaultModernWheel, pixelScale: 2)
    try? modern.writePreview(to: dir.appendingPathComponent("modern.png"))
```

- [ ] **Step 3: 编译并导出预览**

Run: 编译应用，然后 `build/Build/Products/Debug/ping-signals.app/Contents/MacOS/ping-signals --render-wheels /tmp/ping-preview && open /tmp/ping-preview/modern.png`
Expected: 9 帧横排图：8 格轮盘，偶数格外延渐变，金色描边中心，中心有标记图标和「Cancel」；每帧依次高亮一格（从正上开始顺时针）。和原版 lolPing 的轮盘外观对照（可以用 `open ~/sandbox/lolping-fork/release/mac-arm64/lolPing.app` 再按 ⌥+拖动对比）。

- [ ] **Step 4: Commit**

```bash
git add App/Overlay/ModernWheelRenderer.swift App/main.swift
git commit -m "Render modern eight-slice wheel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 音效播放

**Files:**
- Create: `App/Audio/SoundPlayer.swift`

- [ ] **Step 1: 实现**

`App/Audio/SoundPlayer.swift`：

```swift
import AVFoundation
import PingCore

/// Plays pre-decoded sounds with low latency. At most 8 overlap; more are skipped (the ping still shows).
/// The engine starts on the first sound and stops after a few idle seconds, so an idle app costs no CPU.
@MainActor
final class SoundPlayer {
  private static let voices = 8
  private static let idleStop: TimeInterval = 5

  private let engine = AVAudioEngine()
  private var buffers: [String: AVAudioPCMBuffer] = [:]
  private var players: [AVAudioPlayerNode] = []
  private var busy = Set<Int>()
  private var stopTimer: Timer?

  init(names: [String]) {
    var format: AVAudioFormat?
    for name in names {
      guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
            let file = try? AVAudioFile(forReading: url),
            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            (try? file.read(into: buf)) != nil else {
        NSLog("ping-signals: sound \(name) failed to load")
        continue
      }
      buffers[name] = buf
      format = format ?? file.processingFormat
    }
    for _ in 0..<Self.voices {
      let p = AVAudioPlayerNode()
      engine.attach(p)
      engine.connect(p, to: engine.mainMixerNode, format: format)
      players.append(p)
    }
  }

  func play(_ name: String, volume: Float) {
    guard volume > 0, let buf = buffers[name],
          let i = players.indices.first(where: { !busy.contains($0) }) else { return }
    if !engine.isRunning {
      do { try engine.start() } catch { NSLog("ping-signals: audio engine failed: \(error)"); return }
    }
    stopTimer?.invalidate()
    stopTimer = nil
    busy.insert(i)
    let p = players[i]
    p.volume = volume
    p.scheduleBuffer(buf, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
      Task { @MainActor in self?.finished(i) }
    }
    p.play()
  }

  private func finished(_ i: Int) {
    players[i].stop()
    busy.remove(i)
    guard busy.isEmpty else { return }
    stopTimer = Timer.scheduledTimer(withTimeInterval: Self.idleStop, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.busy.isEmpty else { return }
        self.engine.stop()
      }
    }
  }
}
```

- [ ] **Step 2: 编译应用确认无错**

Run: 编译应用 → Expected: `** BUILD SUCCEEDED **`（试听放在 Task 14 手动验证）。

- [ ] **Step 3: Commit**

```bash
git add App/Audio/SoundPlayer.swift
git commit -m "Add low-latency sound player that idles its engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: 覆盖层、轮盘图层与标记动画

**Files:**
- Create: `App/Overlay/WheelLayer.swift`, `App/Overlay/OverlayController.swift`, `App/Overlay/ModernPingAnimator.swift`, `App/Overlay/ClassicPingAnimator.swift`

- [ ] **Step 1: 轮盘图层**

`App/Overlay/WheelLayer.swift`：

```swift
import QuartzCore
import PingCore

/// Shows a WheelArt at a point and highlights the slice under the pointer. Never redraws: it only
/// toggles which pre-rendered image layers are visible.
@MainActor
final class WheelLayer {
  let root = CALayer()
  private let underLayer = CALayer(), overLayer = CALayer(), hotCenter = CALayer()
  private var highlightLayers: [CALayer] = []
  private var art: WheelArt?
  private var origin = CGPoint.zero
  private(set) var hot: Int?

  init() {
    root.isHidden = true
    root.addSublayer(underLayer)
    root.addSublayer(overLayer)
    root.addSublayer(hotCenter)
  }

  func setArt(_ art: WheelArt) {
    self.art = art
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    highlightLayers.forEach { $0.removeFromSuperlayer() }
    highlightLayers = art.highlights.map { img in
      let l = CALayer()
      l.contents = img
      l.isHidden = true
      return l
    }
    for l in highlightLayers { root.insertSublayer(l, above: underLayer) }
    underLayer.contents = art.under
    overLayer.contents = art.over
    hotCenter.contents = art.centerHot
    root.bounds = CGRect(origin: .zero, size: art.size)
    for l in [underLayer, overLayer, hotCenter] + highlightLayers {
      l.bounds = CGRect(origin: .zero, size: art.size)
      l.position = CGPoint(x: art.size.width / 2, y: art.size.height / 2)
      l.contentsScale = art.scale
    }
    CATransaction.commit()
  }

  /// `p` in the hosting view's coordinates (AppKit, y up).
  func open(at p: CGPoint) {
    origin = p
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.position = p
    root.isHidden = false
    setHot(nil)
    CATransaction.commit()
  }

  /// Returns true when a different slice (not the dead zone) became highlighted.
  @discardableResult
  func move(to p: CGPoint) -> Bool {
    guard !root.isHidden else { return false }
    let slice = pick(p)
    guard slice != hot else { return false }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    setHot(slice)
    CATransaction.commit()
    return slice != nil
  }

  /// Closes the wheel; the chosen slice, or nil in the dead zone.
  func release(at p: CGPoint) -> Int? {
    guard !root.isHidden else { return nil }
    let slice = pick(p)
    close()
    return slice
  }

  func close() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.isHidden = true
    setHot(nil)
    CATransaction.commit()
  }

  /// The wheel centre in the hosting view's coordinates.
  var center: CGPoint { origin }

  private func pick(_ p: CGPoint) -> Int? {
    guard let art else { return nil }
    // View coordinates are y up; pickSlice wants y down.
    return WheelGeometry.pickSlice(dx: Double(p.x - origin.x), dy: Double(origin.y - p.y),
                                   slots: art.slots, deadZone: Double(art.deadZone))
  }

  private func setHot(_ slice: Int?) {
    hot = slice
    for (i, l) in highlightLayers.enumerated() { l.isHidden = i != slice }
    hotCenter.isHidden = slice != nil
  }
}
```

- [ ] **Step 2: 新版标记动画**

`App/Overlay/ModernPingAnimator.swift`（时间与几何来自 `overlay.css`；视图坐标 y 向上，CSS 的「向下」在这里是 −y）：

```swift
import AppKit
import QuartzCore
import PingCore

/// League's current ping effect, after lolPing's overlay.css.
@MainActor
enum ModernPingAnimator {
  static func spawn(_ def: PingDef, at p: CGPoint, size s: CGFloat, duration dur: CFTimeInterval, in parent: CALayer) -> CALayer {
    let color = Drawing.color(def.color)
    let root = CALayer()
    root.position = p
    root.bounds = .zero

    // Ground glow: an ellipse under the ping.
    let ground = CAGradientLayer()
    ground.type = .radial
    ground.colors = [color, Drawing.color(def.color, alpha: 0)]
    ground.startPoint = CGPoint(x: 0.5, y: 0.5)
    ground.endPoint = CGPoint(x: 1, y: 1)
    ground.bounds = CGRect(x: 0, y: 0, width: 0.84 * s, height: 0.24 * s)
    ground.position = CGPoint(x: 0, y: -0.32 * s)
    ground.opacity = 0
    ground.add(keyframes("opacity", [0, 0.75, 0.55, 0], [0, 0.1, 0.85, 1], dur), forKey: "ground")
    root.addSublayer(ground)

    // Three rings bursting outward.
    for delay in [0.0, 0.22, 1.4] {
      let ring = CALayer()
      ring.bounds = CGRect(x: 0, y: 0, width: 1.09 * s, height: 1.09 * s)
      ring.cornerRadius = 0.545 * s
      ring.borderWidth = 3
      ring.borderColor = color
      ring.shadowColor = color
      ring.shadowOpacity = 1
      ring.shadowRadius = 9
      ring.shadowOffset = .zero
      ring.opacity = 0
      let scale = CABasicAnimation(keyPath: "transform.scale")
      scale.fromValue = 0.25
      scale.toValue = 1.35
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.95
      fade.toValue = 0
      let g = CAAnimationGroup()
      g.animations = [scale, fade]
      g.duration = 0.65
      g.beginTime = CACurrentMediaTime() + delay
      g.timingFunction = CAMediaTimingFunction(name: .easeOut)
      ring.add(g, forKey: "ring")
      root.addSublayer(ring)
    }

    // The art: pops in, bobs, fades in the last 13 %.
    let art = CALayer()
    art.bounds = CGRect(x: 0, y: 0, width: s, height: s)
    art.position = CGPoint(x: 0, y: 0.23 * s)
    art.add(keyframes("opacity", [1, 1, 0], [0, 0.87, 1], dur), forKey: "life")
    art.opacity = 0   // model value after the animation ends
    root.addSublayer(art)

    let bob = CALayer()
    bob.frame = art.bounds
    art.addSublayer(bob)
    let bobAnim = CABasicAnimation(keyPath: "transform.translation.y")
    bobAnim.fromValue = 0
    bobAnim.toValue = 5
    bobAnim.duration = 0.8
    bobAnim.autoreverses = true
    bobAnim.repeatCount = .infinity
    bobAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bobAnim.beginTime = CACurrentMediaTime() + (def.art.count == 2 ? 0.5 : 0.3)
    bob.add(bobAnim, forKey: "bob")

    func image(_ name: String) -> CALayer {
      let l = CALayer()
      l.contents = Textures.named(name)
      l.contentsGravity = .resizeAspect
      l.frame = CGRect(x: 0, y: 0, width: s, height: s)
      l.shadowColor = color
      l.shadowOpacity = 1
      l.shadowRadius = 10
      l.shadowOffset = .zero
      return l
    }

    if def.art.count == 2 {
      // All In: two halves slide in and clash, a flash, a shake.
      let clash = CALayer()
      clash.frame = bob.bounds
      bob.addSublayer(clash)
      let a1 = image(def.art[0]), a2 = image(def.art[1])
      clash.addSublayer(a1)
      clash.addSublayer(a2)
      a1.add(slide(from: CGPoint(x: 0.64 * s, y: 0.64 * s)), forKey: "slide")
      a2.add(slide(from: CGPoint(x: -0.64 * s, y: 0.64 * s)), forKey: "slide")
      let shake = CAKeyframeAnimation(keyPath: "transform.translation")
      shake.values = [CGSize.zero, CGSize(width: -3, height: -2), CGSize(width: 3, height: 2), CGSize(width: -2, height: 1), CGSize.zero]
        .map { NSValue(size: $0) }
      shake.duration = 0.25
      shake.beginTime = CACurrentMediaTime() + 0.22
      clash.add(shake, forKey: "shake")
      let flash = CAGradientLayer()
      flash.type = .radial
      flash.colors = [CGColor(gray: 1, alpha: 1), color, Drawing.color(def.color, alpha: 0)]
      flash.locations = [0, 0.4, 1]
      flash.startPoint = CGPoint(x: 0.5, y: 0.5)
      flash.endPoint = CGPoint(x: 1, y: 1)
      flash.frame = CGRect(x: 0.25 * s, y: 0.25 * s, width: 0.5 * s, height: 0.5 * s)
      flash.opacity = 0
      let fs = CABasicAnimation(keyPath: "transform.scale")
      fs.fromValue = 0.3
      fs.toValue = 2.2
      let fo = CAKeyframeAnimation(keyPath: "opacity")
      fo.values = [0, 1, 0]
      fo.keyTimes = [0, 0.3, 1]
      let fg = CAAnimationGroup()
      fg.animations = [fs, fo]
      fg.duration = 0.35
      fg.beginTime = CACurrentMediaTime() + 0.2
      fg.timingFunction = CAMediaTimingFunction(name: .easeOut)
      flash.add(fg, forKey: "flash")
      bob.addSublayer(flash)
    } else {
      let pop = image(def.art[0])
      bob.addSublayer(pop)
      let ps = CAKeyframeAnimation(keyPath: "transform.scale")
      ps.values = [0.4, 1.15, 1]
      ps.keyTimes = [0, 0.6, 1]
      ps.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.2, 1.6, 0.4, 1), CAMediaTimingFunction(controlPoints: 0.2, 1.6, 0.4, 1)]
      let po = CAKeyframeAnimation(keyPath: "opacity")
      po.values = [0, 1, 1]
      po.keyTimes = [0, 0.6, 1]
      let pg = CAAnimationGroup()
      pg.animations = [ps, po]
      pg.duration = 0.28
      pop.add(pg, forKey: "pop")
    }

    parent.addSublayer(root)
    return root
  }

  static func keyframes(_ path: String, _ values: [Double], _ times: [Double], _ dur: CFTimeInterval) -> CAKeyframeAnimation {
    let a = CAKeyframeAnimation(keyPath: path)
    a.values = values
    a.keyTimes = times.map { NSNumber(value: $0) }
    a.duration = dur
    return a
  }

  private static func slide(from offset: CGPoint) -> CAAnimation {
    let t = CABasicAnimation(keyPath: "transform.translation")
    t.fromValue = NSValue(size: CGSize(width: offset.x, height: offset.y))
    t.toValue = NSValue(size: .zero)
    let o = CABasicAnimation(keyPath: "opacity")
    o.fromValue = 0
    o.toValue = 1
    let g = CAAnimationGroup()
    g.animations = [t, o]
    g.duration = 0.22
    g.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.9, 0.5)
    return g
  }
}
```

- [ ] **Step 3: 经典标记动画**

`App/Overlay/ClassicPingAnimator.swift`：

```swift
import AppKit
import QuartzCore
import PingCore

/// The pre-12.22 ping: a tinted base ring flat on the ground, the icon dropping onto it.
/// The game used particle effects we can't read, so this follows their look rather than their numbers.
@MainActor
enum ClassicPingAnimator {
  /// Ground-plane squash for the base rings.
  static let groundSquash: CGFloat = 0.45
  /// Icon pixels → points: an icon 128 px wide is 0.55 × size wide.
  static let iconScale: CGFloat = 0.55 / 128

  static func spawn(_ def: PingDef, at p: CGPoint, size s: CGFloat, duration dur: CFTimeInterval, in parent: CALayer) -> CALayer {
    let root = CALayer()
    root.position = p
    root.bounds = .zero
    let fadeIn = 0.2 / dur

    for (i, name) in def.base.enumerated() {
      let base = CALayer()
      base.contents = Textures.tinted(name, def.color)
      let d = i == 0 ? s : 1.3 * s
      base.bounds = CGRect(x: 0, y: 0, width: d, height: d * groundSquash)
      base.position = .zero
      base.opacity = 0
      if i == 0 {
        let sc = CABasicAnimation(keyPath: "transform.scale")
        sc.fromValue = 0.6
        sc.toValue = 1
        sc.duration = 0.2
        sc.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let op = ModernPingAnimator.keyframes("opacity", [0, 1, 1, 0], [0, fadeIn, 0.85, 1], dur)
        let g = CAAnimationGroup()
        g.animations = [sc, op]
        g.duration = dur
        base.add(g, forKey: "base")
      } else {
        // Enemy Missing's outer ring: grows and fades once.
        let sc = CABasicAnimation(keyPath: "transform.scale")
        sc.fromValue = 0.8
        sc.toValue = 1.4
        let op = ModernPingAnimator.keyframes("opacity", [0, 0.8, 0], [0, 0.2, 1], 1.2)
        let g = CAAnimationGroup()
        g.animations = [sc, op]
        g.duration = 1.2
        base.add(g, forKey: "outer")
      }
      root.addSublayer(base)
    }

    guard let name = def.art.first, let img = Textures.named(name) else {
      parent.addSublayer(root)
      return root
    }
    let w = CGFloat(img.width) * iconScale * s, h = CGFloat(img.height) * iconScale * s
    let life = CALayer()
    life.bounds = CGRect(x: 0, y: 0, width: w, height: h)
    life.anchorPoint = CGPoint(x: 0.5, y: 0)           // bottom centre sits on the base
    life.position = .zero
    life.opacity = 0
    life.add(ModernPingAnimator.keyframes("opacity", [0, 1, 1, 0], [0, fadeIn, 0.85, 1], dur), forKey: "life")
    root.addSublayer(life)

    let icon = CALayer()
    icon.contents = img
    icon.frame = life.bounds
    life.addSublayer(icon)
    let drop = CAKeyframeAnimation(keyPath: "transform.translation.y")
    drop.values = [0.3 * s, -0.04 * s, 0]
    drop.keyTimes = [0, 0.7, 1]
    drop.duration = 0.25
    drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
    icon.add(drop, forKey: "drop")
    let bob = CABasicAnimation(keyPath: "transform.translation.y")
    bob.fromValue = 0
    bob.toValue = 4
    bob.duration = 0.8
    bob.autoreverses = true
    bob.repeatCount = .infinity
    bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bob.beginTime = CACurrentMediaTime() + 0.3
    icon.add(bob, forKey: "bob")

    parent.addSublayer(root)
    return root
  }
}
```

- [ ] **Step 4: 覆盖层控制器**

`App/Overlay/OverlayController.swift`：

```swift
import AppKit
import QuartzCore
import PingCore

/// One transparent, click-through panel per screen, above fullscreen apps, on every Space.
@MainActor
final class OverlayController {
  static let maxPings = 60

  @MainActor
  private final class Panel {
    let window: NSPanel
    let screenFrame: CGRect
    let wheel = WheelLayer()
    let pings = CALayer()

    init(screen: NSScreen) {
      screenFrame = screen.frame
      window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      window.isOpaque = false
      window.backgroundColor = .clear
      window.hasShadow = false
      window.ignoresMouseEvents = true
      window.level = .screenSaver
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.wantsLayer = true
      view.layer?.addSublayer(pings)
      view.layer?.addSublayer(wheel.root)
      window.contentView = view
      window.setFrame(screen.frame, display: false)
      window.orderFrontRegardless()
    }
  }

  private var panels: [Panel] = []
  private var wheelPanel: Panel?
  private var art: WheelArt?
  private var observer: NSObjectProtocol?

  init() {
    rebuild()
    observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.rebuild() }
    }
  }

  func setWheelArt(_ art: WheelArt) {
    self.art = art
    for p in panels { p.wheel.setArt(art) }
  }

  private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

  private func rebuild() {
    for p in panels { p.window.orderOut(nil) }
    panels = NSScreen.screens.map { Panel(screen: $0) }
    wheelPanel = nil
    if let art { setWheelArt(art) }
  }

  private func panel(forGlobal g: GesturePoint) -> (Panel, CGPoint)? {
    let gp = CGPoint(x: g.x, y: g.y)
    let a = ScreenMath.appKitPoint(fromGlobal: gp, primaryHeight: primaryHeight)
    guard let p = panels.first(where: { $0.screenFrame.contains(a) }) ?? panels.first else { return nil }
    return (p, ScreenMath.localPoint(fromGlobal: gp, screenFrame: p.screenFrame, primaryHeight: primaryHeight))
  }

  private func local(_ g: GesturePoint, in p: Panel) -> CGPoint {
    ScreenMath.localPoint(fromGlobal: CGPoint(x: g.x, y: g.y), screenFrame: p.screenFrame, primaryHeight: primaryHeight)
  }

  func openWheel(at g: GesturePoint) {
    guard let (p, l) = panel(forGlobal: g) else { return }
    wheelPanel = p
    p.wheel.open(at: l)
  }

  /// True when a new slice became highlighted (for the tick sound).
  func moveWheel(to g: GesturePoint) -> Bool {
    guard let p = wheelPanel else { return false }
    return p.wheel.move(to: local(g, in: p))
  }

  /// The chosen slice and the wheel centre in global coordinates, or nil.
  func releaseWheel(at g: GesturePoint) -> (slice: Int, center: GesturePoint)? {
    guard let p = wheelPanel else { return nil }
    let center = p.wheel.center
    let slice = p.wheel.release(at: local(g, in: p))
    wheelPanel = nil
    guard let slice else { return nil }
    let a = CGPoint(x: center.x + p.screenFrame.minX, y: center.y + p.screenFrame.minY)
    let gc = ScreenMath.globalPoint(fromAppKit: a, primaryHeight: primaryHeight)
    return (slice, GesturePoint(Int(gc.x.rounded()), Int(gc.y.rounded())))
  }

  func cancelWheel() {
    wheelPanel?.wheel.close()
    wheelPanel = nil
  }

  func spawnPing(_ def: PingDef, style: WheelStyle, at g: GesturePoint, size: CGFloat, duration: Double) {
    guard let (p, l) = panel(forGlobal: g) else { return }
    while (p.pings.sublayers?.count ?? 0) >= Self.maxPings { p.pings.sublayers?.first?.removeFromSuperlayer() }
    let layer = style == .classic
      ? ClassicPingAnimator.spawn(def, at: l, size: size, duration: duration, in: p.pings)
      : ModernPingAnimator.spawn(def, at: l, size: size, duration: duration, in: p.pings)
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(duration + 0.15))
      layer.removeFromSuperlayer()
    }
  }

  /// The centre of the screen under the mouse, in global coordinates (for preview pings).
  func mouseScreenCenter() -> GesturePoint {
    let mouse = NSEvent.mouseLocation
    let f = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens[0]).frame
    let g = ScreenMath.globalPoint(fromAppKit: CGPoint(x: f.midX, y: f.midY), primaryHeight: primaryHeight)
    return GesturePoint(Int(g.x), Int(g.y))
  }
}
```

- [ ] **Step 5: 编译应用确认无错**

Run: 编译应用 → Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 6: Commit**

```bash
git add App/Overlay/WheelLayer.swift App/Overlay/OverlayController.swift App/Overlay/ModernPingAnimator.swift App/Overlay/ClassicPingAnimator.swift
git commit -m "Add overlay panels, wheel layer, classic and modern ping animations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: EventTap 与全屏检测

**Files:**
- Create: `App/Input/EventTap.swift`, `App/Input/FullscreenProbe.swift`

- [ ] **Step 1: 全屏检测**

`App/Input/FullscreenProbe.swift`：

```swift
import AppKit
import PingCore

/// Is the topmost normal window under a global point a fullscreen app (a game)? Called only when a
/// gesture would start, so the window list query (~1 ms) never runs on ordinary clicks.
@MainActor
enum FullscreenProbe {
  static func isFullscreen(x: Int, y: Int) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
    let p = CGPoint(x: x, y: y)
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    let screens = NSScreen.screens.map { ScreenMath.globalRect(ofScreenFrame: $0.frame, primaryHeight: primaryHeight) }
    for w in list {  // front to back
      guard (w[kCGWindowLayer as String] as? Int) == 0,
            let dict = w[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: dict),
            bounds.contains(p) else { continue }
      return screens.contains { abs($0.minX - bounds.minX) < 1 && abs($0.minY - bounds.minY) < 1
        && abs($0.width - bounds.width) < 1 && abs($0.height - bounds.height) < 1 }
    }
    return false
  }
}
```

- [ ] **Step 2: EventTap**

`App/Input/EventTap.swift`：

```swift
import AppKit
import PingCore

/// Session-level CGEventTap feeding GestureMachine. Needs Accessibility permission.
@MainActor
final class EventTap {
  /// "LPIN" in eventSourceUserData marks events we post ourselves.
  private static let selfMarker: Int64 = 0x4C50_494E

  private let machine: GestureMachine
  private let onEmit: (GestureEmit) -> Void
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var flags: UInt64 = 0
  private var watchdog: Timer?

  init(machine: GestureMachine, onEmit: @escaping (GestureEmit) -> Void) {
    self.machine = machine
    self.onEmit = onEmit
  }

  var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

  /// False when the tap can't be created (no Accessibility permission).
  func start() -> Bool {
    if tap != nil { return true }
    let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                                .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                .keyDown, .keyUp, .flagsChanged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, refcon in
      let me = Unmanaged<EventTap>.fromOpaque(refcon!).takeUnretainedValue()
      let swallow = MainActor.assumeIsolated { me.handle(type, event) }
      return swallow ? nil : Unmanaged.passUnretained(event)
    }
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: callback,
                                    userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
    tap = t
    source = CFMachPortCreateRunLoopSource(nil, t, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    resync()
    watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.apply(self.machine.tick(nowMs: Self.nowMs()))
      }
    }
    return true
  }

  func stop() {
    watchdog?.invalidate()
    watchdog = nil
    if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
    if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
    tap = nil
    source = nil
  }

  /// Runs a machine call made outside the tap (config change, enable/disable) through the same output path.
  func apply(_ out: GestureOutput) {
    for e in out.emits { onEmit(e) }
    for r in out.replays {
      switch r {
      case .buttonDown(let b): post(b, down: true)
      case .buttonUp(let b): post(b, down: false)
      }
    }
  }

  // MARK: Tap

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
      resync()
      return false
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.selfMarker { return false }
    let t = Self.nowMs()
    feedFlags(event.flags.rawValue, t)
    if type == .flagsChanged { return false }

    if type == .keyDown || type == .keyUp {
      let vk = KeyMap.keyCodeToVK(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
      if vk == 0 { return false }
      return run(InputEvent(kind: type == .keyDown ? .keyDown : .keyUp, vk: vk, timeMs: t))
    }

    let loc = event.location
    var e = InputEvent(kind: .mouseMove, x: Int(loc.x.rounded()), y: Int(loc.y.rounded()), timeMs: t)
    switch type {
    // Dragged events always pass: dropping them at the session tap freezes the cursor.
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: e.kind = .mouseMove
    case .leftMouseDown: e.kind = .mouseDown; e.button = .left
    case .leftMouseUp: e.kind = .mouseUp; e.button = .left
    case .rightMouseDown: e.kind = .mouseDown; e.button = .right
    case .rightMouseUp: e.kind = .mouseUp; e.button = .right
    case .otherMouseDown, .otherMouseUp:
      switch event.getIntegerValueField(.mouseEventButtonNumber) {
      case 2: e.button = .middle
      case 3: e.button = .x1
      case 4: e.button = .x2
      default: return false
      }
      e.kind = type == .otherMouseDown ? .mouseDown : .mouseUp
    default: return false
    }
    let swallow = run(e)
    return e.kind == .mouseMove ? false : swallow
  }

  private func run(_ e: InputEvent) -> Bool {
    let out = machine.onEvent(e)
    apply(out)
    return out.swallow
  }

  /// Turns modifier-flag changes into the key events the machine expects. Mouse events carry flags too,
  /// which keeps the state right while Secure Event Input hides keyboard events from the tap.
  private func feedFlags(_ raw: UInt64, _ t: UInt64) {
    let f = raw & KeyMap.Flag.all
    guard f != flags else { return }
    for k in KeyMap.modifierTransitions(from: flags, to: f) {
      apply(machine.onEvent(InputEvent(kind: k.down ? .keyDown : .keyUp, vk: k.vk, timeMs: t)))
    }
    flags = f
  }

  private func resync() {
    let now = CGEventSource.flagsState(.combinedSessionState).rawValue
    feedFlags(now, Self.nowMs())
    let modifierVKs: Set<UInt32> = [VK.lShift, VK.rShift, VK.lControl, VK.rControl, VK.lOption, VK.rOption, VK.lCommand, VK.rCommand]
    machine.syncKeyStates { vk in
      if modifierVKs.contains(vk) { return KeyMap.modifierHeld(now, vk) }
      guard let code = KeyMap.vkToKeyCode(vk) else { return false }
      return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
    }
  }

  private func post(_ b: MouseButton, down: Bool) {
    let type: CGEventType, button: CGMouseButton
    switch b {
    case .left: type = down ? .leftMouseDown : .leftMouseUp; button = .left
    case .right: type = down ? .rightMouseDown : .rightMouseUp; button = .right
    case .middle: type = down ? .otherMouseDown : .otherMouseUp; button = .center
    case .x1: type = down ? .otherMouseDown : .otherMouseUp; button = CGMouseButton(rawValue: 3)!
    case .x2: type = down ? .otherMouseDown : .otherMouseUp; button = CGMouseButton(rawValue: 4)!
    case .none: return
    }
    let pos = CGEvent(source: nil)?.location ?? .zero
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pos, mouseButton: button) else { return }
    e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    e.flags = CGEventFlags(rawValue: flags)       // a replayed ⌥-click keeps its ⌥
    e.setIntegerValueField(.eventSourceUserData, value: Self.selfMarker)
    e.post(tap: .cghidEventTap)
  }

  private static func nowMs() -> UInt64 { UInt64(ProcessInfo.processInfo.systemUptime * 1000) }
}
```

- [ ] **Step 3: 编译应用确认无错**

Run: 编译应用 → Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: Commit**

```bash
git add App/Input
git commit -m "Add CGEventTap input and fullscreen probe

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: 授权、菜单栏、协调器——接通整条链路（**用户确认节点**）

**Files:**
- Create: `App/AccessibilityGate.swift`, `App/MenuBarController.swift`, `App/Signals/PingEffectHandler.swift`, `App/AppCoordinator.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1: 授权检测**

`App/AccessibilityGate.swift`：

```swift
import AppKit
import ApplicationServices

/// Waits for Accessibility permission, then calls `onGranted` once. Plan 2 replaces the system prompt
/// with a guidance window.
@MainActor
final class AccessibilityGate {
  private var timer: Timer?

  var isTrusted: Bool { AXIsProcessTrusted() }

  func waitForPermission(onGranted: @escaping () -> Void) {
    if isTrusted { onGranted(); return }
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
      MainActor.assumeIsolated {
        guard AXIsProcessTrusted() else { return }
        t.invalidate()
        self?.timer = nil
        onGranted()
      }
    }
  }

  static func openSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }
}
```

- [ ] **Step 2: 标记效果处理器**

`App/Signals/PingEffectHandler.swift`：

```swift
import PingCore

/// v1's only signal handler: draws the ping and plays its sound.
@MainActor
final class PingEffectHandler: SignalHandler {
  private let overlay: OverlayController
  private let sound: SoundPlayer
  private let settings: () -> Settings

  init(overlay: OverlayController, sound: SoundPlayer, settings: @escaping () -> Settings) {
    self.overlay = overlay
    self.sound = sound
    self.settings = settings
  }

  func handle(_ signal: PingSignal) {
    let s = settings()
    guard let def = PingCatalog.def(signal.ping, style: signal.style) else { return }
    overlay.spawnPing(def, style: signal.style, at: signal.point, size: CGFloat(s.pingSizePx), duration: s.pingDurationS)
    if !s.muted { sound.play(def.sound, volume: Float(s.volume) / 100) }
  }
}
```

- [ ] **Step 3: 菜单栏**

`App/MenuBarController.swift`：

```swift
import AppKit
import PingCore

@MainActor
final class MenuBarController: NSObject {
  struct Actions {
    var toggleEnabled: () -> Void
    var setStyle: (WheelStyle) -> Void
    var preview: (PingID) -> Void
  }

  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let actions: Actions

  init(actions: Actions) {
    self.actions = actions
    super.init()
    item.button?.image = NSImage(systemSymbolName: "exclamationmark.bubble.fill", accessibilityDescription: "ping-signals")
  }

  /// Rebuilds the menu for the current state.
  func update(enabled: Bool, style: WheelStyle, needsPermission: Bool) {
    item.button?.appearsDisabled = !enabled || needsPermission
    let menu = NSMenu()
    if needsPermission {
      menu.addItem(entry("需要「辅助功能」权限… / Grant Accessibility…") { AccessibilityGate.openSettings() })
      menu.addItem(.separator())
    }
    let toggle = entry(enabled ? "暂停 / Pause" : "启用 / Enable") { [actions] in actions.toggleEnabled() }
    toggle.keyEquivalent = "p"
    toggle.keyEquivalentModifierMask = [.control, .option]
    menu.addItem(toggle)

    let styleMenu = NSMenu()
    for (s, title) in [(WheelStyle.classic, "经典（2022）/ Classic"), (.modern, "新版 / Modern")] {
      let i = entry(title) { [actions] in actions.setStyle(s) }
      i.state = s == style ? .on : .off
      styleMenu.addItem(i)
    }
    let styleItem = NSMenuItem(title: "轮盘风格 / Wheel Style", action: nil, keyEquivalent: "")
    styleItem.submenu = styleMenu
    menu.addItem(styleItem)

    let previewMenu = NSMenu()
    let ids = PingCatalog.wheel(style: style, modernWheel: PingCatalog.defaultModernWheel) + [.generic]
    for id in ids { previewMenu.addItem(entry(id.rawValue) { [actions] in actions.preview(id) }) }
    let previewItem = NSMenuItem(title: "预览标记 / Preview Ping", action: nil, keyEquivalent: "")
    previewItem.submenu = previewMenu
    menu.addItem(previewItem)

    menu.addItem(.separator())
    menu.addItem(entry("退出 / Quit") { NSApp.terminate(nil) })
    item.menu = menu
  }

  private func entry(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
    let i = ClosureMenuItem(title: title, action: action)
    return i
  }
}

/// NSMenuItem that runs a closure.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
  private let run: () -> Void
  init(title: String, action: @escaping () -> Void) {
    run = action
    super.init(title: title, action: #selector(fire), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError("unused") }
  @objc private func fire() { run() }
}
```

（菜单文字先用中英并列，Plan 2 换成本地化字符串。预览菜单里新版风格列的是默认 8 格；Plan 2 有轮盘编辑后改为读设置。）

- [ ] **Step 4: 协调器**

`App/AppCoordinator.swift`：

```swift
import AppKit
import PingCore

@MainActor
final class AppCoordinator {
  private let store = SettingsStore()
  private(set) var settings: Settings
  private let machine = GestureMachine()
  private let overlay = OverlayController()
  private let sound = SoundPlayer(names: PingCatalog.allSounds)
  private let bus = SignalBus()
  private let gate = AccessibilityGate()
  private var tap: EventTap!
  private var menu: MenuBarController!

  init() {
    settings = store.load()
    tap = EventTap(machine: machine) { [weak self] e in self?.handle(e) }
    menu = MenuBarController(actions: .init(
      toggleEnabled: { [weak self] in self?.toggleEnabled() },
      setStyle: { [weak self] s in self?.setStyle(s) },
      preview: { [weak self] id in self?.preview(id) }))
    bus.register(PingEffectHandler(overlay: overlay, sound: sound) { [weak self] in self?.settings ?? Settings() })
    machine.fullscreenProbe = { x, y in MainActor.assumeIsolated { FullscreenProbe.isFullscreen(x: x, y: y) } }
    tap.apply(machine.setConfig(settings.gestureConfig(enabled: settings.enabledOnStart)))
    refreshWheelArt()
    refreshMenu()
    gate.waitForPermission { [weak self] in
      guard let self else { return }
      if !self.tap.start() { NSLog("ping-signals: event tap failed to start") }
      self.refreshMenu()
    }
  }

  // MARK: Gesture output

  private var currentWheel: [PingID] { PingCatalog.wheel(style: settings.style, modernWheel: settings.wheel) }

  private func handle(_ e: GestureEmit) {
    switch e {
    case .wheelOpen(let p):
      overlay.openWheel(at: p)
    case .wheelMove(let p):
      if overlay.moveWheel(to: p) && settings.tickSound && !settings.muted {
        sound.play(PingCatalog.tickSound, volume: Float(settings.volume) / 100)
      }
    case .wheelRelease(let p):
      if let r = overlay.releaseWheel(at: p), r.slice < currentWheel.count {
        emitSignal(currentWheel[r.slice], at: r.center, source: .wheel)
      }
    case .click(let p):
      emitSignal(PingCatalog.clickPing(style: settings.style, modernClickPing: settings.clickPingID), at: p, source: .click)
    case .cancel:
      overlay.cancelWheel()
    case .toggled:
      refreshMenu()
    }
  }

  private func emitSignal(_ id: PingID, at p: GesturePoint, source: PingSignal.Source) {
    bus.emit(PingSignal(ping: id, style: settings.style, point: p,
                        frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                        time: Date(), source: source))
  }

  // MARK: Menu actions

  private func toggleEnabled() {
    tap.apply(machine.setEnabled(!machine.enabled))
    refreshMenu()
  }

  private func setStyle(_ s: WheelStyle) {
    settings.style = s
    store.save(settings)
    overlay.cancelWheel()
    refreshWheelArt()
    refreshMenu()
  }

  private func preview(_ id: PingID) {
    emitSignal(id, at: overlay.mouseScreenCenter(), source: .click)
  }

  private func refreshWheelArt() {
    let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    let art = settings.style == .classic
      ? ClassicWheelRenderer.render(wheel: currentWheel, pixelScale: scale)
      : ModernWheelRenderer.render(wheel: currentWheel, pixelScale: scale)
    overlay.setWheelArt(art)
  }

  private func refreshMenu() {
    menu.update(enabled: machine.enabled, style: settings.style, needsPermission: !gate.isTrusted)
  }
}
```

- [ ] **Step 5: 在 AppDelegate 里创建协调器**

把 `App/AppDelegate.swift` 改为：

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var coordinator: AppCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    coordinator = AppCoordinator()
  }
}
```

- [ ] **Step 6: 编译、跑测试**

Run: 跑测试（确认 Core 仍全绿），再编译应用 → Expected: 都成功。

- [ ] **Step 7: 运行并完成手动检查**

Run: `open build/Build/Products/Debug/ping-signals.app`
首次运行：系统弹出辅助功能授权提示 → 在「系统设置 → 隐私与安全性 → 辅助功能」打开 **ping-signals**（不是 Electron）→ 1 秒内生效，无需重启。

按设计文档 9.2 手动清单逐项检查（本计划可验证的部分）：
1. 授权后无需重启即可使用
2. 经典风格：⌥+拖动出现 4 格轮盘，上/右/下/左分别高亮，松开在**轮盘圆心**放出 危险 / 正在路上 / 请求协助 / 敌人消失，音效正确；死区松开取消。菜单切到「新版」后 8 格轮盘立即生效
3. Esc / 右键取消；在 Finder 里 ⌥+单击、⌥+拖动文件等正常操作不受影响（单击会被补发）
5. 全屏视频（如 QuickTime 全屏）里 ⌥+点击不被拦截
6. 多显示器（如有）：轮盘与标记出现在光标所在屏幕
7. ⌃⌥P 暂停/恢复，菜单栏图标变灰/恢复

- [ ] **Step 8: 🔶 用户确认节点**

请用户亲自试用并确认：
- 经典标记动画观感（用菜单「预览标记」在屏幕中央逐个放出，也可实际 ⌥+拖动）
- 经典「危险」音效是否就是老版的声音（`GetBack`）
- 轮盘大小

调整只改 `ClassicPingAnimator` 的常量（`groundSquash`、`iconScale`、时长）或 `ClassicPingAnimator`/`ClassicWheelRenderer` 的摆放；危险音效不对时，在 `PingCatalog.classicDefs` 换成其他已有音效并重跑 `import-assets.sh` 与测试。

- [ ] **Step 9: Commit**

```bash
git add App
git commit -m "Wire gesture, overlay, sound and signal bus; menu bar with style switch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: 性能验收与文档

**Files:**
- Create: `scripts/measure.sh`
- Modify: `CLAUDE.md`、`WORKLOG.md`（两者全局 gitignore，不提交）

- [ ] **Step 1: 写测量脚本**

`scripts/measure.sh`（与测 Electron 基线时用的方法相同）：

```bash
#!/bin/bash
# usage: scripts/measure.sh <pgrep pattern> <seconds>
# Prints each matching process's phys_footprint, the total, and the average CPU over <seconds>.
set -euo pipefail
P=$(pgrep -f "$1")
total=0
for p in $P; do
  name=$(ps -o comm= -p "$p" | sed 's|.*/||')
  kb=$(footprint "$p" 2>/dev/null | awk '/phys_footprint:/{v=$2; u=$3; if (u=="MB") v*=1024; if (u=="GB") v*=1048576; print int(v); exit}')
  echo "$p $name ${kb:-0} KB"
  total=$((total + ${kb:-0}))
done
echo "total footprint: $((total / 1024)) MB"
cpu() { ps -o time= -p $(echo $P | tr ' ' ',') | awk -F'[:.]' '{s+=$1*60+$2+$3/100} END{printf "%.2f", s}'; }
a=$(cpu); sleep "$2"; b=$(cpu)
echo "CPU avg over ${2}s: $(echo "($b-$a)/$2*100" | bc -l | cut -c1-5)%"
```

- [ ] **Step 2: Release 编译并测量**

Run:
```bash
chmod +x scripts/measure.sh
xcodebuild build -project PingSignals.xcodeproj -scheme PingSignals -configuration Release -derivedDataPath build -quiet
open build/Build/Products/Release/ping-signals.app
sleep 15
scripts/measure.sh "ping-signals.app" 60
du -sh build/Build/Products/Release/ping-signals.app
```
（Release 包签名身份相同，授权保持有效；若系统再次要求授权，先授权再测量。）
Expected（设计文档 1.2 节目标）：总内存 < 50 MB；60 s 平均 CPU < 0.5 %；.app < 15 MB。不达标时用 Instruments（Time Profiler / Allocations）定位，修复后重测。

- [ ] **Step 3: 记录结果**

把实测数值追加到 `WORKLOG.md`（格式 `- 2026-10-12 — Plan 1 done; idle footprint X MB, CPU Y %, app Z MB`），并更新 `CLAUDE.md` 的 Structure（列出 `Core/`、`App/`、`Tests/`、`scripts/`）与 Notes（生成工程、跑测试、编译、预览轮盘的命令）。

- [ ] **Step 4: Commit**

```bash
git add scripts/measure.sh
git commit -m "Add performance measurement script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## 后续计划（本计划完成后编写）

- **Plan 2：设置与本地化** — SwiftUI 设置窗口（触发 / 轮盘编辑器 / 标记与声音 / 应用）、授权引导窗口、开机自启（SMAppService）、快捷键与自定义触发键录制、`Localizable.xcstrings`（zh-Hans / en）替换菜单里的中英并列文字。
- **Plan 3：发布与自动更新** — 确定正式名称与 bundle id、Sparkle 2 集成与 EdDSA 密钥、`scripts/release.sh`、创建 GitHub 仓库与首个 Release、更新后授权保持验证。
