# ping-signals 设计文档（v3：定制化 / Plan 2）

- 日期：2026-10-12
- 前置：v1 `2026-10-12-ping-signals-design.md`（§7 设置、引导、自启、多语言），v2 `2026-10-12-ping-actions-design.md`（标记动作）。
- 本文档是 v1 §7 的补充与修订；冲突时以本文为准。

## 1. 目标

让别的用户不改代码就能用出自己的味道：每个标记绑定自选动作，并补齐 v1 规格里的设置窗口、首次引导、开机自启、暂停键录制和中英文界面。

## 2. 动作绑定

### 2.1 模型

- 按 `PingID` 绑定（11 种标记，含普通标记 `generic`），**两种轮盘风格共用**。
- 默认值 = v2 的固定对照：危险 → 撤退，正在路上 → 待办面板，请求协助 → 呼叫 Claude，其他 → 无。
- 菜单栏预览（`.preview`）照旧不触发动作。

```swift
public enum ActionConfig: Equatable, Sendable, Codable {
  case none, retreat, todoPanel, claudeQuickEntry
  case shortcut(String)    // 快捷指令名称
  case keystroke(Hotkey)   // 可以不带修饰键（如 F13）
  case open(String)        // 网址、xxx:// 链接，或 file:///…/X.app
  case shell(String)       // 一行 shell 命令
}
```

JSON 形如 `{"type":"shortcut","value":"翻译剪贴板"}`；`Settings.actions: [PingID: ActionConfig]`（编码为以 PingID 为键的对象）。宽容解码：逐条解析，坏条目 / 未知类型 / 未知 PingID 跳过，缺失的 PingID 用默认值。`shortcut` / `open` / `shell` 的值为空白时运行时视同「无」。

### 2.2 执行（`ActionRunner`，App 层）

| 类型 | 执行 |
|---|---|
| 撤退 / 待办面板 / 呼叫 Claude | v2 现有实现，不变 |
| 运行快捷指令 | `/usr/bin/shortcuts run <名称> --input-path <临时文件>`，输入为上下文 JSON（见 2.3）；后台进程，不等结果 |
| 按快捷键 | 等物理修饰键松开后（`SyntheticInput.whenModifiersReleased`），用 CGEvent 发送 keyDown/keyUp，带修饰键 flags 和自标记 |
| 打开应用或网址 | `NSWorkspace.shared.open(URL)`；无法解析为带 scheme 的 URL 则记日志不执行 |
| 运行 Shell 命令 | `/bin/zsh -lc <命令>`，继承本应用环境并追加 2.3 的变量；stdin/stdout/stderr 接 `/dev/null`；非零退出只记日志。不弹确认 |

失败一律只记 `NSLog`，不弹窗、不影响动画音效。

### 2.3 上下文

快捷指令和 Shell 需要上下文时，在动作执行前采集（复用 `ContextCapture`）。浏览器网址最多等 1 s，超时则不带网址。

环境变量 / JSON 字段（值缺失时不设置 / 省略）：

| 变量 | JSON 键 | 内容 |
|---|---|---|
| `PING_ID` | `ping` | 标记 ID，如 `danger` |
| `PING_STYLE` | `style` | `classic` / `modern` |
| `PING_X` / `PING_Y` | `x` / `y` | 全局坐标（主屏左上角为原点） |
| `FRONT_APP` | `app` | 前台应用名称 |
| `FRONT_BUNDLE_ID` | `bundleID` | 前台应用 bundle id |
| `WINDOW_TITLE` | `windowTitle` | 前台窗口标题 |
| `FRONT_URL` | `url` | 浏览器当前网址 |

### 2.4 「试一下」

设置窗口中的「试一下」直接调用 `ActionRunner.run(config, signal:)`，绕过 `ActionRouter`；上下文为点击时的前台应用（即本应用设置窗口，属预期）。

## 3. 设置窗口

SwiftUI，`NSWindow` + `NSHostingController`，五个分页，修改即时生效并保存。菜单新增「设置…」（⌘,）。

1. **触发**：触发键（⌥ / ⌃ / ⇧ / ⌘ / 鼠标 4 / 鼠标 5 / 录制自定义按键）、拖动阈值滑块（2–40）、「触发键 + 单击放标记」、「全屏游戏中放行」。
2. **轮盘**：只有两张轮盘图片（经典 / 新版），点击选择风格。不提供格子编辑：新版固定为默认 8 格，单击标记固定为普通标记（2026-10-12 用户决定，替代 v1 的拖放编辑器）。
3. **标记与声音**：大小（60–220）、时长（1–8 s）、音量、静音、轮盘提示音。
4. **动作**：每个标记一行：名称 + 类型下拉 + 参数控件 + 「试一下」。参数控件：快捷指令下拉（`shortcuts list` 读取，可刷新）、快捷键录制器、网址文本框 + 「选择应用…」（`NSOpenPanel`）、命令文本框。经典轮盘的 4 种 + 普通标记在上，新版专有的 6 种放在可折叠的「新版轮盘」分组。「恢复默认」。
5. **通用**：暂停快捷键录制、开机自启、语言（自动 / 简体中文 / English，提示重启生效，带「立即重启」按钮）、版本号。自动更新开关留给 Plan 3。

### 3.1 应用设置变更

`AppCoordinator.apply(_ new: Settings)`：保存 → `machine.setConfig(...)`（同时取消进行中的手势，修复「切换风格不重置手势」）→ 刷新轮盘贴图 → 刷新菜单 → 若 `launchAtLogin` 变化则调用 `SMAppService`。菜单栏的风格切换也走 `apply`。

### 3.2 按键录制

录制时暂停手势状态机（`setSuspended(true)`），避免当前暂停键被吞；本地 `NSEvent` 监听 keyDown（以及 flagsChanged，用于只按修饰键的触发键录制）；Esc 取消录制。暂停快捷键必须含 ⌃ / ⌥ / ⌘；自定义触发键不能等于暂停键的主键——不合法时录制器显示红字提示且不保存。

### 3.3 按键显示名

`KeyNames`（PingCore）：VK → 显示名（A–Z、0–9、F1–F20、⏎ ⇥ ␣ ⌫ ⎋ ↑↓←→ 等），`Hotkey` → `⌃⌥P` 形式。菜单的暂停项显示当前暂停键；能映射为单字符的设为菜单 keyEquivalent。

## 4. 首次引导

替换系统权限弹窗：未授权时显示引导窗口（说明 + 「打开系统设置」按钮），每 1 s 轮询，授权后自动关闭并启动事件监听。运行中权限被收回时不自动弹窗，菜单里的「需要辅助功能权限…」会打开这个窗口。

## 5. 开机自启

`SMAppService.mainApp.register()` / `unregister()`。设置窗口打开时读取实际状态（用户可能在系统设置里改过）并回写 `launchAtLogin`。

## 6. 多语言

- `App/Resources/en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`，代码中以英文为键（`String(localized:)`）。
- 标记名称沿用 LoL 官方中文译名。
- 语言非「自动」时，启动最早期把 `AppleLanguages` 写成对应语言；「自动」时移除该覆盖。修改后重启生效。

## 7. 测试

- 单元测试（PingCore）：`ActionConfig` 编解码与宽容解码、默认对照、`ActionContext` 环境变量 / JSON、`KeyNames`。
- 手动：7 种动作逐一试；设置窗口每项即时生效；暂停键录制后菜单显示更新；开机自启；中英文切换；首次引导（撤销权限后重新授权）。
- 设置窗口与引导窗口先用 `--render-settings <dir>` 导出预览图，用户确认后再替换正在运行的应用。
