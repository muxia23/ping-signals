# ping-signals 设计文档（v2：标记动作）

- 日期：2026-10-12
- 前置：v1 设计 `2026-10-12-ping-signals-design.md`；Plan 1 已实现 `SignalBus` / `SignalHandler` / `PingSignal`。

## 1. 目标

让部分标记在放出时触发一个具体动作，标记从「表情」变成「信号」。

## 2. 标记与动作

| 标记 | 动作 | 行为 |
|---|---|---|
| ？敌人消失 | 无 | 只有动画与音效 |
| 📍 普通标记（⌥+单击） | 无 | 只有动画与音效 |
| 🚩 请求协助 | **打开 Claude 快速输入框** | 模拟双击 ⌥（Claude 桌面版默认的 Quick Entry 快捷键） |
| ↓ 正在路上 | **侧边待办面板** | 从屏幕右侧滑出待办面板，立即可输入 |
| ！危险 | **撤退** | 隐藏所有应用窗口；再打一次危险恢复原样 |

新版 8 格轮盘中同名的标记（危险、正在路上、请求协助、敌人消失）用同样的动作；推进、全力进攻、需要视野、敌方视野、诱饵、视野已清除无动作。动作在标记动画与音效之后同步触发（同一次 `SignalBus.emit` 中，`PingEffectHandler` 先注册）。

## 3. 架构

```
SignalBus ──▶ PingEffectHandler（v1，动画 + 音效）
          └─▶ ActionRouter ──▶ PingAction（按 PingID 查表）
                                 ├─ ClaudeQuickEntryAction
                                 ├─ TodoPanelAction ──▶ TodoPanelController ──▶ TodoStore
                                 └─ RetreatAction
```

- `ActionRouter: SignalHandler`：持有 `[PingID: PingAction]` 对照表（代码内固定；Plan 2 设置窗口可开放配置）。
- `protocol PingAction { @MainActor func perform(_ signal: PingSignal) }`。
- 纯逻辑放 `PingCore` 并单元测试：动作对照表、`TodoItem` / `TodoStore`（增删改、持久化、宽容解码）、撤退状态机（`RetreatState`：记录被隐藏的应用与原前台应用，决定下一次是撤退还是恢复）。
- 系统交互放 App：按键模拟、浏览器地址读取、窗口隐藏 / 恢复、面板 UI。

## 4. 请求协助：Claude 快速输入框

- 发送两次 ⌥ 按下 / 抬起的 `flagsChanged` 事件（左 Option），两次间隔约 80 ms；事件带 `eventSourceUserData = 0x4C50494E` 自标记，自己的 EventTap 会跳过，不会误触发轮盘。
- 若 Claude.app 未运行，先 `NSWorkspace.openApplication` 启动并等待其就绪（最多 3 s）再发送。
- **风险**：Claude 可能不识别模拟的双击 ⌥。实现计划的第一个任务即验证；不行则回到用户，改为让用户在 Claude 设置中指定组合键（如 ⌃⌥⌘C）后模拟该组合键。

## 5. 正在路上：侧边待办面板

### 5.1 面板

- 屏幕右侧（光标所在屏幕）滑出的面板，宽 360 pt、高为屏幕可见高度，动画 0.2 s。
- `NSPanel`（`.nonactivatingPanel` 但可成为 key window），置顶于普通窗口之上，出现时输入框获得焦点。
- 顶部输入框：回车保存为新待办（空文本不保存），保存后输入框清空、面板保持打开；Esc 或点击面板外收起。
- 下方列表（SwiftUI）：未完成在上、按创建时间倒序；已完成折叠在底部「已完成（N）」。每行：复选框、文字、来源行（应用图标 + 窗口标题，或网址的域名）、相对时间。
- 行操作：勾选完成 / 取消；右键或滑动删除；双击文字编辑；**点击来源行跳回**：有网址则用默认浏览器打开该网址，否则激活该应用（应用已退出则启动它）。
- 再次打「正在路上」时，若面板已打开则只把焦点放回输入框。

### 5.2 上下文采集（打标记那一刻）

- 前台应用：`NSWorkspace.frontmostApplication` 的名称与 bundle id。
- 窗口标题：通过辅助功能 API 读前台应用的 focused window 的 `kAXTitleAttribute`（已有辅助功能权限）。
- 网址：前台应用是 Safari / Chrome / Arc / Edge / Brave 时，用 AppleScript 读当前标签页 URL（首次需要用户授予「自动化」权限；被拒绝时不记网址，不影响保存）。
- 上下文在面板弹出**之前**采集（面板弹出后前台应用会变成本应用）。

### 5.3 存储

- `~/Library/Application Support/ping-signals/todos.json`，`[TodoItem]`：
  `id (UUID), text, createdAt, doneAt?, appName?, bundleID?, windowTitle?, url?`
- 每次修改后原子写入；读取时逐条宽容解码（坏条目跳过，不丢其他条目）。

## 6. 危险：撤退

- **撤退**（当前未处于撤退状态）：记录当前前台应用；对所有 `activationPolicy == .regular`、未隐藏、非本应用的运行中应用调用 `hide()`，记下被隐藏的列表。Finder 也隐藏（桌面图标保留）。
- **恢复**（处于撤退状态）：对记录中仍在运行且仍隐藏的应用 `unhide()`，最后激活原前台应用；清空状态。
- 撤退状态只存在内存中；应用重启后视为未撤退。
- 用户在撤退期间手动打开了别的应用不影响恢复（只恢复记录中的应用）。

## 7. 测试

- 单元测试（PingCore）：`ActionRouter` 对照表（两种风格下每个 PingID 的动作）、`TodoStore`（增 / 完成 / 删 / 编辑 / 排序 / 持久化 / 宽容解码）、`RetreatState`（撤退 → 恢复 → 再撤退；恢复时跳过已退出的应用；原前台应用记录）。
- 手动：请求协助能唤出 Claude 快速输入框（Claude 运行中 / 未运行两种）；正在路上在 Safari、Chrome、Finder、VS Code 中分别打，上下文正确、点击可跳回；撤退 / 恢复往返 3 次窗口状态一致；轮盘在撤退状态下仍可用。
