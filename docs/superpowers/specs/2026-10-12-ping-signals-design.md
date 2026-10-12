# ping-signals 设计文档（v1：Swift 原生移植）

- 日期：2026-10-12
- 代号：`ping-signals`（正式名在首次发布前确定，见「待定事项」）
- 参考来源：[darrenprx/lolPing](https://github.com/darrenprx/lolPing) v0.5.1（MIT），本地副本 `~/sandbox/lolping-fork/`

## 1. 目标

把 lolPing 的「桌面 LoL 标记轮盘」重写为**单一 Swift 原生 macOS 应用**，只保留标记功能，并为后续「每个标记触发一个动作（信号）」预留接口。

### 1.1 范围

**保留**

- 触发键 + 左键拖动 → 轮盘 → 松开放标记（动画 + 音效）
- 触发键 + 单击直接放标记（可选，默认关）
- 设置窗口（触发、轮盘编辑、标记与声音、应用）
- 暂停/恢复快捷键（默认 ⌃⌥P）、开机自启
- 自动更新（Sparkle 2 + GitHub Releases）
- 中英双语界面
- 全屏应用中放行点击（原版仅 Windows 有效，本版实现 macOS 版）

**移除**

- 表情轮盘（含自定义表情导入、49 MB 表情素材）
- 房间（Nostr 中继、局域网、加密、成员标签）
- Windows 支持及 Windows 专属逻辑（菜单键屏蔽等）

**不在 v1 范围（v2 再做）**

- 任何标记绑定的具体动作（如问号 = 记录疑问 + 截图）。v1 只提供 `SignalHandler` 接口。

### 1.2 成功标准

在 M1 Pro 上空闲状态（仅覆盖层，无标记）测得：

| 指标 | Electron 版实测 | v1 目标 |
|---|---|---|
| 内存（全部进程 phys_footprint 合计） | ~490 MB | < 50 MB |
| 空闲 CPU（60 s 平均） | 7–12 % | ≈ 0 %（< 0.5 %） |
| .app 体积 | 343 MB | < 15 MB |

并且行为与原版一致（见第 9 节手动清单）。

## 2. 技术选型

- 语言：Swift 6，AppKit（覆盖层、菜单栏）+ SwiftUI（设置窗口）+ Core Animation（轮盘与标记动画）
- 输入：`CGEventTap`（会话级，需「辅助功能」权限）
- 音频：`AVAudioEngine` + 预加载 `AVAudioPCMBuffer`
- 自动更新：Sparkle 2（SPM 依赖）
- 开机自启：`SMAppService.mainApp`
- 工程：XcodeGen `project.yml`（生成的 `.xcodeproj` 不入库），最低 macOS 14
- 测试：Swift Testing（`import Testing`）

## 3. 架构

```
EventTap ──InputEvent──▶ GestureMachine ──GestureOutput──▶ AppCoordinator
                              ▲                               │
                    FullscreenProbe                ┌──────────┼─────────────┐
                                                   ▼          ▼             ▼
                                            OverlayController  SignalBus   MenuBar/Toggle
                                            (WheelView)          │
                                                                 ▼
                                                      [SignalHandler]
                                                      v1: PingEffectHandler
                                                      (PingAnimator + SoundPlayer)
```

数据只单向流动：输入 → 手势判断 → 协调器 → 覆盖层 / 信号。`GestureMachine` 是纯逻辑，不依赖任何系统 API。

### 3.1 模块与文件划分

| 模块 | 职责 | 依赖 |
|---|---|---|
| `Input/EventTap.swift` | 安装 CGEventTap，转 `InputEvent`，执行 `GestureOutput` 中的「吞掉/补发」；超时被禁用时重新启用并 resync | GestureMachine |
| `Input/KeyCodes.swift` | 修饰键 flags → 按键按下/抬起；keyCode 定义 | — |
| `Input/GestureMachine.swift` | 移植 `decision.cpp` 的状态机（只含单一轮盘） | — |
| `Input/FullscreenProbe.swift` | 判断某点下方是否为全屏应用窗口 | CoreGraphics |
| `Overlay/OverlayController.swift` | 每屏一个透明 `NSPanel`，坐标换算，分派到 WheelView / 标记层 | — |
| `Overlay/WheelGeometry.swift` | 轮盘常量 + `pickSlice` | — |
| `Overlay/WheelView.swift` | 绘制轮盘、高亮扇区 | WheelGeometry |
| `Overlay/PingAnimator.swift` | 标记动画（CALayer + CAKeyframeAnimation） | PingCatalog |
| `Audio/SoundPlayer.swift` | 预加载与播放音效 | — |
| `Signals/PingSignal.swift` | `PingSignal`、`SignalHandler`、`SignalBus` | — |
| `Signals/PingEffectHandler.swift` | v1 唯一处理器：动画 + 音效 | PingAnimator, SoundPlayer |
| `Model/PingCatalog.swift` | 11 种标记定义（id、贴图、音效、颜色） | — |
| `Model/Settings.swift` | 设置结构、默认值、校验、`UserDefaults` 持久化 | — |
| `App/AppCoordinator.swift` | 串联各模块，响应设置变化 | 全部 |
| `App/MenuBarController.swift` | 菜单栏图标与菜单 | — |
| `App/AccessibilityGate.swift` | 权限检测、引导窗口、轮询授权 | — |
| `App/LoginItem.swift` | 开机自启 | ServiceManagement |
| `App/Updater.swift` | Sparkle 封装 | Sparkle |
| `Settings/*.swift` | SwiftUI 设置窗口各分组、轮盘编辑器 | Settings |

## 4. 输入与手势（Input）

### 4.1 EventTap

- 监听事件：鼠标左/右/其他键 down/up、mouseMoved、各类 dragged、keyDown/keyUp、flagsChanged。
- 每个事件先用其 flags 推导修饰键的按下/抬起（移植 `feedFlags` / `modifierTransitions`），保证在「安全输入」（密码框）屏蔽键盘事件时修饰键状态仍正确。
- 自己补发的事件写入 `eventSourceUserData = 0x4C50494E` 标记，回到 tap 时直接放行。
- **拖动事件永远放行**（在会话层丢弃会冻结光标）。
- 收到 `tapDisabledByTimeout` / `ByUserInput`：重新启用并 `resync()`（按系统真实状态清除已抬起却未观察到的按键）。
- 补发按键：`CGEvent(mouseEventSource:...)` 发往 `.cghidEventTap`，保留当前 flags（补发的 ⌥+单击仍带 ⌥）。

### 4.2 GestureMachine

从 `native/hook-helper/src/decision.{h,cpp}` 移植，删去 `WheelKind.emote`、`maskMenuKeys`、Windows 注入键。接口：

```swift
struct GestureConfig { trigger: Trigger; clickPing: Bool; gameCheck: Bool
                       dragThresholdPx: Int; toggle: Hotkey; enabled: Bool }
enum Trigger { case option, control, shift, command, mouse4, mouse5, key(UInt16) }

struct GestureOutput { var swallow = false; var emits: [GestureEmit] = []; var replays: [Replay] = [] }
enum GestureEmit { case wheelOpen(CGPoint), wheelMove(CGPoint), wheelRelease(CGPoint),
                   click(CGPoint), cancel, toggled(Bool) }

final class GestureMachine {
  func setConfig(_:) -> GestureOutput
  func setEnabled(_:) -> GestureOutput
  func onEvent(_: InputEvent) -> GestureOutput
  func tick(nowMs: UInt64) -> GestureOutput          // 10 s 看门狗
  func syncKeyStates(isDown: (Key) -> Bool)
  var fullscreenProbe: ((CGPoint) -> Bool)?
}
```

状态：`idle → pending → wheel → swallowUp`。规则（与原版一致）：

1. 触发键按住 + 左键按下（鼠标侧键触发时为该侧键按下）→ 吞掉，进入 `pending`，记录起点。
2. `pending` 中移动超过 `dragThresholdPx` → `wheelOpen(起点)`，进入 `wheel`；之后的移动 → `wheelMove`。
3. `wheel` 中松开 → `wheelRelease(点)`；按 Esc 或右键 → `cancel`（右键的抬起也吞掉）。
4. `pending` 中松开未拖动：`clickPing` 开 → `click(点)`；关 → 补发原来的按下 + 抬起。
5. 触发键按住期间按了任何非修饰键 → `foreignKey`，直到所有触发键松开前不拦截点击。
6. `gameCheck` 开且 `fullscreenProbe(点)` 为真 → 不拦截该次按下。
7. 暂停快捷键按下 → 切换 `enabled` 并吞掉该键，发 `toggled`；暂停时除快捷键外全部放行。
8. 触发键为自定义按键或鼠标侧键时，该键本身被吞掉（不传给其他应用）。
9. 看门狗：非 `idle` 且 10 s 无鼠标事件 → 取消并回到 `idle`。

### 4.3 FullscreenProbe

`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 取点下最上层的普通窗口（layer 0），若其 bounds 等于所在屏幕 frame 即视为全屏。结果按 PID 缓存 500 ms，避免每次点击都查询。

## 5. 覆盖层（Overlay）

### 5.1 OverlayController

- 每个 `NSScreen` 一个 `NSPanel`：`styleMask = [.borderless, .nonactivatingPanel]`，`isOpaque = false`，`backgroundColor = .clear`，`ignoresMouseEvents = true`，`level = .screenSaver`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，`hasShadow = false`。
- 监听 `NSApplication.didChangeScreenParametersNotification` 重建面板。
- 坐标：tap 给的是全局坐标（原点在主屏左上，y 向下）；转换为对应屏幕面板内的本地坐标（AppKit 原点在左下）。
- 空闲时无任何图层动画，不产生 CPU 占用。

### 5.2 WheelGeometry / WheelView

常量（与 `src/shared/geometry.ts` 一致，单位 pt）：`innerR 86, outerR 188, extR 288, iconR 137, iconSize 48`。

```swift
// 偏移 (dx, dy)，屏幕坐标 y 向下。死区内返回 nil，否则 0...7（0 = 北，顺时针）
func pickSlice(dx: CGFloat, dy: CGFloat, deadZone: CGFloat = innerR) -> Int?
// deg = (atan2(dy, dx)·180/π + 90 + 22.5 + 360) mod 360; slice = floor(deg/45) mod 8
```

绘制（`CAShapeLayer` / `CAGradientLayer(type: .radial)`），复刻 `wheel.ts`：

- 偶数扇区在 outerR…extR 之间画外延渐变（#5c6066，0.55 → 0）。
- 环：innerR…outerR，径向渐变 #2a2d31 → #4a4e54，不透明度 0.92。
- 扇区分隔线：#a08a5c，不透明度 0.45，线宽 1.2。
- 高亮扇区：径向渐变 #8a8f96 → #9aa0a8 → 透明，fill-opacity 0.55；偶数扇区延伸到 extR。
- 中心：innerR 圆，#2c5d60 → #11292c，金色描边 #c8aa6e 3pt；内圈 #8a7448 1pt。
- 中心图标 + 文字（本地化「取消」提示），每格图标位于 iconR。
- 高亮变化时（且轮盘已打开）播放提示音 `button`（受「轮盘提示音」开关控制）。
- 松开时返回选中 ping，标记位置为**轮盘圆心**，不是松开点。

### 5.3 PingAnimator

按 `overlay.css` 复刻，`size` = 设置的 `pingSizePx`（默认 110），`dur` = `pingDurationS`（默认 3.2 s）：

| 层 | 几何（相对标记点，size 的倍数） | 动画 |
|---|---|---|
| ground 光斑 | x −0.42, y +0.2, 宽 0.84, 高 0.24，椭圆径向渐变（颜色 → 透明） | 不透明度 0 → 0.75（10 %）→ 0.55（85 %）→ 0，时长 dur |
| ring ×3 | 直径 1.09，3pt 描边 + 18pt 发光 | scale 0.25 → 1.35、不透明度 0.95 → 0，0.65 s；延迟 0 / 0.22 / 1.4 s |
| art 图标 | 中心偏上 0.23，边长 1.0，10pt 同色投影 | 整体：0–87 % 不透明，最后 13 % 淡出 |
| pop（单图） | — | scale 0.4 → 1.15（60 %）→ 1，0.28 s，弹性曲线；0.3 s 起 ±5pt 上下浮动，周期 1.6 s |
| clash（All In） | 两半图分别从右上 / 左上 0.64·size 处滑入 0.22 s | 0.22 s 起抖动 0.25 s；闪光 scale 0.3 → 2.2、0.35 s，延迟 0.2 s；0.5 s 起浮动 |

同屏上限 60 个，超出时移除最早的。每个标记在 `dur + 0.15 s` 后移除图层。

### 5.4 SoundPlayer

启动时把 12 个用到的音效（11 种标记 + `button`）解码为 `AVAudioPCMBuffer`；`AVAudioEngine` 带 8 个 `AVAudioPlayerNode` 组成的播放池，最多同时 8 个声音，超出则跳过（标记照常显示）。音量 = `volume / 100`，静音时不播放。

### 5.5 素材

从 `lolping-fork/assets` 只复制 `PingCatalog` 引用的贴图（约 20 个 PNG，约 0.5 MB）和 12 个音效。音效用 `afconvert -f m4af -d aac` 转换为 `.m4a`。

## 6. 信号接口（Signals）

```swift
struct PingSignal: Sendable {
  let ping: PingID
  let point: CGPoint            // 全局坐标（y 向下）
  let screenID: CGDirectDisplayID
  let frontApp: String?         // bundle identifier
  let time: Date
  let source: Source            // .wheel / .click
  enum Source: Sendable { case wheel, click }
}
@MainActor protocol SignalHandler: AnyObject { func handle(_ signal: PingSignal) }
@MainActor final class SignalBus {
  func register(_ h: SignalHandler)
  func emit(_ s: PingSignal)    // 按注册顺序同步调用
}
```

v1 只注册 `PingEffectHandler`。某个处理器出错不得影响其他处理器（处理器内部自行处理错误，`handle` 不抛错）。

## 7. 应用外壳

### 7.1 菜单栏与生命周期

- `LSUIElement = YES`（无程序坞图标）。
- 菜单：启用/暂停（显示当前快捷键）· 设置… · 检查更新… · 退出。暂停时图标变灰。
- 启动时 `enabledOnStart` 决定初始状态（默认开）。

### 7.2 辅助功能授权

- 启动时 `AXIsProcessTrusted()`；未授权则显示引导窗口（说明 + 「打开系统设置」按钮，跳转 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`）。
- 每 1 s 轮询，授权后立即安装 EventTap、关闭引导窗口。
- 运行中权限被撤销（tap 创建失败或被禁用且无法重新启用）→ 回到引导状态。

### 7.3 设置

```swift
struct Settings: Codable, Equatable {
  var version = 1
  var enabledOnStart = true
  var trigger: Trigger = .option
  var dragThresholdPx = 8          // 2...40
  var clickPing = false
  var clickPingID: PingID = .generic
  var gameCheck = true
  var wheel: [PingID] = [.danger, .push, .omw, .allin, .assist, .needvision, .missing, .enemyvision]
  var toggleHotkey = Hotkey(mods: [.control, .option], key: .p)
  var pingSizePx = 110             // 60...220
  var pingDurationS = 3.2          // 1...8，步长 0.1
  var volume = 70                  // 0...100
  var muted = false
  var tickSound = true
  var launchAtLogin = false
  var language: LanguagePref = .auto   // .auto / .zhHans / .en
  var autoUpdateCheck = true
}
```

- 以 JSON 存入 `UserDefaults`。读取时逐字段解码，缺失或非法字段回落到默认值（数值裁剪到范围内；`wheel` 必须恰好 8 个互不相同的合法 ID，否则整体回落默认）。
- 校验规则：暂停快捷键必须包含 ⌃、⌥ 或 ⌘ 之一；自定义触发键不能与暂停快捷键的主键相同。
- 设置变更立即生效（重新下发 `GestureConfig`、刷新轮盘图标、更新登录项）。

### 7.4 设置窗口（SwiftUI）

分组：

1. **触发**：触发键选择（⌥ / ⌃ / ⇧ / ⌘ / 鼠标 4 / 鼠标 5 / 录制自定义按键）、拖动阈值滑块、「触发键 + 单击放标记」开关、全屏应用中暂停开关。
2. **轮盘**：圆形编辑器，8 格 + 中心（中心 = 单击放的标记）。从下方 11 种标记池拖到格子；格子间拖动互换；拖到已存在的标记时两格互换（移植 `placeOnSlot` / `swapSlots` / `dropPatch`）。单击某个标记预览动画。「恢复默认」按钮。
3. **标记与声音**：大小、时长、音量滑块，静音、轮盘提示音开关。
4. **应用**：暂停快捷键录制、开机自启、自动检查更新 + 「立即检查」、语言、版本号。

### 7.5 多语言

`Localizable.xcstrings`，zh-Hans + en。语言设置为非「自动」时，通过 `AppleLanguages` 覆盖本应用的语言，重启后生效（设置项旁提示）。标记名称沿用 LoL 官方中文译名（危险、推进、正在路上、全力进攻、请求协助、需要视野、敌人消失、敌方视野、标记、诱饵、视野已清除）。

### 7.6 开机自启

`SMAppService.mainApp.register()` / `unregister()`；设置窗口打开时读取实际状态（用户可能在系统设置里改过）。

### 7.7 自动更新

- Sparkle 2，`SUFeedURL` = `https://raw.githubusercontent.com/<owner>/<repo>/main/appcast.xml`。
- `SUPublicEDKey` 写入 Info.plist；私钥由 `generate_keys` 生成并存于钥匙串，不入库。
- `autoUpdateCheck` 控制 `automaticallyChecksForUpdates`；菜单与设置中的「检查更新」随时可用。

## 8. 构建、签名、发布

- `project.yml`：一个 app target + 一个 unit test target；SPM 依赖 Sparkle。
- `scripts/make-cert.sh`：在登录钥匙串创建自签名代码签名证书（名称如 `ping-signals Local Signing`），只需运行一次。所有构建都用它签名，使 TCC（辅助功能授权）在更新后仍认得应用。
- `scripts/release.sh <version>`：
  1. 修改 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
  2. `xcodebuild archive` + 导出（使用上述证书签名）
  3. `ditto -c -k --keepParent` 打包 zip
  4. Sparkle `sign_update` 生成 EdDSA 签名，更新 `appcast.xml`
  5. 提交 `appcast.xml`，`gh release create v<version> <zip>`
- 未公证：首次打开仍需在「隐私与安全性」中点「仍要打开」。
- 许可：保留原项目 MIT 版权声明（`LICENSE` 中注明移植自 darrenprx/lolPing）；素材为 Riot Games 所有，依据 Riot「Legal Jibber Jabber」政策用于非商业粉丝项目，README 中声明。

## 9. 测试

### 9.1 自动测试（Swift Testing）

- `GestureMachineTests`：从 `native/hook-helper/tests/helper_tests.cpp` 移植与平台无关、与单轮盘相关的用例（拖动开轮盘、阈值、单击补发、clickPing、Esc / 右键取消、foreignKey、暂停快捷键、看门狗、syncKeyStates、自定义键 / 侧键触发、gameCheck 探针）。
- `WheelGeometryTests`：8 个方向 + 扇区边界 ±22.5° + 死区。
- `SettingsTests`：默认值、缺字段回落、越界裁剪、非法 wheel 回落、快捷键校验。
- `WheelEditTests`：`placeOnSlot` / `swapSlots` / `dropPatch`。
- `SignalBusTests`：注册顺序、多处理器分发。

### 9.2 手动清单

1. 首次启动 → 引导授权 → 授权后无需重启即可使用
2. ⌥ + 拖动出现轮盘，8 个方向分别高亮并放出正确标记与音效；死区松开取消
3. Esc / 右键取消；⌥ + 普通单击在其他应用中正常生效（补发）
4. 开启「⌥ + 单击放标记」后单击直接放标记
5. 全屏应用（如全屏 LoL / 全屏视频）中 ⌥ + 点击不被拦截
6. 多显示器：轮盘与标记出现在光标所在屏幕
7. ⌃⌥P 暂停/恢复，菜单栏图标同步
8. 设置各项即时生效；轮盘编辑后轮盘立即更新
9. 开机自启开关与系统设置一致
10. 发布两个版本，从旧版通过 Sparkle 更新到新版，更新后辅助功能授权仍有效

### 9.3 性能验收

用 `footprint` 汇总内存，用 `ps` 的 CPU 时间差计算 60 s 平均 CPU，测量方法与 Electron 版基线相同，结果需满足 1.2 节的目标。

## 10. 待定事项

- **正式名称与 bundle identifier**：首次发布（创建 GitHub 仓库）前确定；确定后不再更改（更改会导致授权与更新失效）。在此之前使用 `ping-signals` / `com.muxia.ping-signals`。
