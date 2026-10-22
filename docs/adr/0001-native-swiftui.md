# ADR-0001：采用 SwiftUI + AppKit 构建 macOS 应用

- 状态：已接受
- 日期：2026-10-22
- 决策者：项目作者

## 背景

精力管理是一个个人使用的 macOS 应用，核心界面只有 4 个页面（开启一天、今日、项目、统计）和 1 个浮动番茄钟，但高度依赖系统级能力：

- 菜单栏常驻（MenuBarExtra）
- 始终置顶的浮动窗口与全局完成弹窗（NSPanel）
- 系统通知与通知操作
- 全局快捷键
- 开机自启（SMAppService）
- 后续可能接入日历（EventKit）与图表（Swift Charts）

现有 HTML 原型是可运行的单文件应用，包含完整的数据模型与计时逻辑，但没有原生窗口、菜单栏、通知和系统权限能力。

## 决策

采用 **SwiftUI + AppKit** 构建原生 macOS 应用。

- UI 使用 SwiftUI；需要精细控制的部分（浮动 `NSPanel`、菜单栏、窗口层级、全局快捷键）用 AppKit 桥接。
- 数据层使用 SQLite + GRDB；App、CLI、MCP 共享 `JingliCore`。
- 不采用 Tauri 2，也不采用 WKWebView 壳。
- HTML 原型只作为设计参考与逻辑规格，不作为运行时依赖。

## 理由

1. 应用的核心体验是系统级 ambient UI，原生路径最短。
2. 页面数量少，SwiftUI 的工作量可控；设计稿的卡片、网格、自定义按钮可以还原。
3. 现有 HTML 逻辑约 500 行，移植到 Swift 比在 WebView 里维护两套状态更干净。
4. 后续接 EventKit、SMAppService、Swift Charts、Focus Status 都更顺。
5. 避免 WebView 的内存、质感和系统集成损耗。

## 后果

### 正面

- 菜单栏、浮动窗口、通知、快捷键、开机自启都能直接用系统 API。
- 单一状态源（Swift Core），UI / CLI / MCP 共享同一套规则。
- 更容易做截图测试与原生可访问性。

### 负面 / 约束

- 需要按设计稿重写 UI，不能直接复用 HTML/CSS。
- 需要维护 Xcode 工程与 Swift 代码。
- `NSPanel` 全局层级、Focus 联动等系统行为仍需真机验证（见计划 8.4）。
- 不做跨平台；仅支持 macOS。

## 备选方案

- **Tauri 2**：可复用 HTML，但浮窗需要 AppKit 桥接，WebView 质感与系统集成不如原生；当前不采用。
- **WKWebView 壳**：最快，但会出现 JS 状态与 Swift 状态两套真相；不采用。
