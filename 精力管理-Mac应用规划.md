# 精力管理 · Mac 应用规划

> 版本：v3.10（P1 重启恢复）  
> 日期：2026-10-22  
> 状态：项目 CRUD / 休息 / 重启恢复实测通过；浮窗位置记忆、真实通知、睡眠唤醒、今日详情待补  
> 输入材料：`精力管理 · Mac 应用设计稿 (1).pdf`、`精力管理 · Mac 应用设计稿.pdf`（v1，含项目页）、`精力管理 · App 图标.pdf`、`项目与任务管理器.html`、`项目与任务管理器-文字稿.txt`
>
> **2026-10-22 范围调整：应用只管理「今天」。不保留历史、不做 7 天 / 30 天图表、不迁移旧番茄历史。PDF 的「近 7 天柱状图」移出 v1。**

---

## 0. 结论摘要

**做原生 SwiftUI 的 macOS 应用；现有 HTML 当功能基线，PDF 当视觉与信息架构基线；v1 只做「选 4 件主线 → 共同番茄钟 → 完成结算 → 统计」的闭环；开始一轮自动进入勿扰、结束 / 废弃自动退出；Agent 输入用 CLI + SKILL.md（MCP 可选，不阻塞 v1），应用内加一个 ⌘K 命令条和 Agent 活动面板。**

核心判断：

- 这个产品的价值不是「又一个待办」，而是「每天限制你只做少量重要的事」。
- Mac 应用的差异化是「常驻但不打扰」：菜单栏、浮动番茄钟、通知、全局快捷键；开始专注时自动进入勿扰，结束自动恢复。
- 先把闭环做扎实；**只管理今天**，不做历史趋势，也不做周复盘。
- Agent 不应该直接操作数据库，应该走统一的 Core API，才能保证 4 个主线、计时分摊等规则不被绕过。

---

## 1. 材料梳理

### 1.1 PDF 设计稿

v2 共 4 页，均为 1440×900 的深色界面。与 v1 相比，v2 用「本轮番茄钟完成」替换了「项目」页；项目页沿用 v1，因此完整设计集共 5 个界面。

| 页面 | 内容 |
|---|---|
| 开启一天 | 按项目分组展示未完成任务，勾选今天要做的事；右上角显示「主线已选 3/4」；底部「开启一天」 |
| 今日清单 | 主线任务 / 临时任务两区；卡片底部左侧番茄数，右侧播放、完成、详情；右下角浮动番茄钟 |
| 本轮番茄钟完成 | 全局置顶弹窗（独立 `NSPanel`，覆盖所有 App、全屏和 Space）：番茄图标、标题「本轮番茄钟完成」、副标题「25 分钟 · 2 件任务共同计时，各记 0.5 个」；参与任务逐行显示 +0.5；主按钮「开始休息 5 分钟」，次按钮「再来一轮」「回到清单」；背景浮窗显示 00:00「本轮结束」 |
| 项目（v1） | 项目卡片网格，显示名称、说明、任务数；支持新建项目、进入项目 |
| 精力统计 | 今日番茄钟、专注时长、完成任务三张 KPI；今日专注记录列表。**v1 不做近 7 天柱状图**（范围收敛为「只管今天」） |

视觉特征：纯黑背景、深色圆角卡片、克制的蓝色选中态、白色主按钮、SF 字体、细边框、低饱和度项目色。

**App 图标**：3D 番茄计时器，黑底；源文件在 `Design/AppIcon/AppIcon.pdf`，已生成 `AppIcon-1024.png`、`Jingli.iconset`、`Jingli.icns`。如果 Finder / Dock 需要 macOS squircle 透明边角，Phase 0 再生成 masked 版本。

### 1.2 HTML 原型

一个可独立运行的单文件应用，样式和脚本全部内嵌，无外部依赖。

代码结构：

- `model.js`：项目 / 任务 / 每日计划的数据模型与校验
- `timer.js`：25 分钟计时器、暂停/继续、共享轮次、历史记录
- `focus-dock.js`：浮动番茄钟、任务选择器、拖拽定位
- `app.js`：页面渲染、事件处理、localStorage 持久化

localStorage 键：

- `liubai.workspace.v1`：项目、任务、每日计划
- `liubai.focus.v1`：当前计时状态
- `liubai.pomodoro.v1.<sessionId>`：已完成的番茄轮次

关键规则：

- 主线任务每天最多 4 个，跨项目共用名额。
- 一轮完整 25 分钟记 1 个番茄，由到时仍参与本轮的任务平均分摊。
- 中途加入的任务参与均分；提前完成或移出的任务不记这一轮。
- 暂停或废弃未完成的轮次不增加统计；同一轮不会因刷新重复累计。
- 累计保留精度，只在显示时保留最多两位小数。

### 1.3 文字稿

行为规格，覆盖：产品定位、视觉与布局、开启一天、今日任务、项目管理、浮动番茄钟、多任务共同计时、番茄钟统计、重置一天、文件使用与数据保存。

### 1.4 已定口径（范围收敛）

1. **只管理今天。** 不保留历史、不做近 7 天 / 30 天图表；统计页只显示「今日番茄钟 / 今日专注时长 / 今日完成任务 + 今日专注记录」。
2. **不迁移旧番茄历史。** HTML 的 `liubai.pomodoro.v1.*` 不导入；只导入当前项目 / 任务 / 今日计划。进行中的计时如果跨天，忽略。
3. **跨天规则。** 未完成任务回到未安排；今日番茄记录清空；已完成任务保留完成状态，可在项目中查看，但不进历史统计。
4. **统计口径。** 日总番茄按整数；单任务按 `1/n` 份额；不做半轮。
5. **时钟结束页。** 休息 5 分钟独立倒计时、可跳过、不计入统计；再来一轮复用未完成任务；完成后浮窗按钮改「关闭」。

---

## 2. 产品定位

### 2.1 一句话

**一个每天只允许你选 4 件主线、用 25 分钟一轮去推进、并回看精力投入的 Mac 应用。**

### 2.2 四个闭环

- **选**：每天最多 4 件主线，跨项目共用名额；临时任务不限。
- **做**：25 分钟一轮，多任务共享倒计时，按参与人数均分。
- **结算**：完成后弹窗展示每个任务的 `+1/n`，可开始 5 分钟休息、再来一轮或回到清单。
- **看**：今天投入多少轮、多少分钟、完成了什么；**不做历史趋势**。

### 2.3 Mac 差异化

不是「多一个平台」，而是「常驻但不打扰」：

- 菜单栏显示倒计时，点开就能暂停 / 继续 / 快速加任务。
- 浮动番茄钟永远置顶，拖到屏幕角落，跨 Space 都在。
- 轮次结束用系统通知 + 声音，通知上直接「开始下一轮 / 休息 5 分钟」。
- 完成弹窗是全局置顶的独立窗口：主窗口关掉、App 在后台、正在用全屏应用，也会出现在最前面；每个任务显示 `+1/n`，可「开始休息 5 分钟」「再来一轮」「回到清单」。
- 开始一轮自动进入勿扰模式，完成 / 废弃 / 退出时自动退出；暂停保持勿扰，休息时恢复通知，再来一轮再进入。
- 全局快捷键：`⌃⌥Space` 呼出浮窗，`⌘⇧N` 快速记录。
- Agent 一句话就能把任务、计划、计时推进去。

### 2.4 非目标（v1 不做）

- 通用待办 / 日历 / 笔记
- 多人协作
- 多设备同步
- 内嵌大模型聊天
- 复杂报表 / 自定义看板
- App Store 上架（个人使用，Developer ID 签名即可）

---

## 3. 技术调研与选型

### 3.1 方案对比

| 方案 | 复用现有 HTML | Mac 原生体验 | 开发成本 | 结论 |
|---|---|---|---|---|
| **SwiftUI + AppKit** | 低（按设计稿重写） | 最好：MenuBarExtra / NSPanel / 通知 / 全局快捷键 / Swift Charts | 中 | **已选定**：长期日用、要原生质感 |
| **Tauri 2** | 高（可直接搬 HTML/CSS/JS） | 较好：官方 tray / notification / global-shortcut / SQL / autostart / window-state 插件；浮窗需 AppKit 桥接 | 低-中 | 备选，不采用 |
| **WKWebView 壳** | 最高 | 一般：原生能力全靠 JS bridge | 最低 | 不采用，只适合原型 |

### 3.2 调研结论

- MCP 现在的标准传输是 **stdio** 和 **Streamable HTTP**；桌面端本地集成用 stdio 最省事，应用侧只要暴露一个本地 socket / HTTP 端点，MCP server 做翻译即可（[MCP Transports](https://modelcontextprotocol.io/docs/concepts/transports)）。
- Agent Skills 已经是公开规范：`SKILL.md` 用 YAML frontmatter（`name` / `description`），正文按需加载，建议主文件控制在 500 行以内，脚本放 `scripts/`（[Agent Skills Specification](https://agentskills.io/specification)）。这正好是「skill 输入」的标准形态。
- Tauri 2 官方插件已经覆盖托盘、通知、全局快捷键、SQL、开机自启、窗口状态（[Tauri Plugins](https://v2.tauri.app/plugin/)），所以 Tauri 是可行的 B 计划。
- 本机工具链已就绪：Xcode 26.0.1、Swift 6.2、macOS 26.6.2、Rust 1.98、Node 20.19。

### 3.3 已确定：SwiftUI 原生（2026-10-22）

**技术栈已定：SwiftUI + AppKit。** 后续不再评估 Tauri / WKWebView，除非遇到 SwiftUI 无法解决的系统级阻塞。

理由：

1. 这个应用的核心体验是系统级 ambient UI（菜单栏、浮窗、通知、全局快捷键），原生路径最短。
2. 只有 4 个页面 + 1 个浮窗，SwiftUI 工作量可控；设计稿的卡片、网格、自定义按钮都能还原。
3. 现有 HTML 的逻辑很小（model / timer 约 500 行），移植到 Swift 比在 WebView 里维护两套状态更干净。
4. 后续接 EventKit（日历）、SMAppService（开机自启）、Swift Charts 都更顺。

**不采用的备选：Tauri 2。** 它能直接复用现有 HTML/CSS/JS，但 WebView 的质感、内存和系统集成深度不如原生，浮窗需要 AppKit 桥接。当前不投入；如果后续遇到原生无法解决的系统级阻塞，再单独评估。

**不采用 WKWebView 壳。** 看起来最快，但会出现「JS 状态 + Swift 状态」两套真相，计时器、菜单栏、通知都要桥接，长期维护最痛。只适合做 1–2 天的可行性原型。

---

## 4. 系统架构

```text
┌─────────────────────────────────────────────┐
│  Kimi Code / Claude Code / Codex            │
│   └─ SKILL.md  (何时调用、约束、示例)         │
│        ├─ jingli CLI  (主路径，人/脚本)       │
│        └─ jingli-mcp  (可选，v1.1)           │
└──────────────────┬──────────────────────────┘
                   │ Unix socket + JSON-RPC (0600)
┌──────────────────▼──────────────────────────┐
│  Jingli.app                                  │
│  ├─ AgentBridge (命令路由/审计/撤销)          │
│  ├─ Core (TaskStore / DayPlan / Timer / Stats)│
│  ├─ SQLite (GRDB, WAL)                       │
│  ├─ SwiftUI (4 页面 + 设置 + ⌘K)             │
│  ├─ MenuBarExtra (倒计时/快捷操作)            │
│  └─ NSPanel (浮动番茄钟)                      │
└─────────────────────────────────────────────┘
```

### 4.1 关键设计

- **单一真相**：所有写操作走 `Core`，UI / CLI 都调它（MCP 可选）；Agent 不直接写 SQLite。
- **计时器在 Core，不在 UI**：存 `endsAt` + `remainingMs` + `phase`；App 重启、睡眠唤醒、时钟跳变都以 Core 为准。
- **完成弹窗独立于主窗口**：不挂在 `WindowGroup` 上，用单独的全局 `NSPanel`；主窗口关闭、App 在后台也能弹出。
- **勿扰联动走 Shortcuts**：macOS 没有公开 API 直接设置 Focus；用「设置专注模式」快捷指令 + `shortcuts run`，不碰私有 API、不做 Control Center UI 脚本。
- **本地优先**：SQLite WAL + 每日 JSON 备份；v1 不做云同步。
- **Agent 走 Unix socket + JSON-RPC**：不监听公网端口，不需要防火墙权限；socket 目录 0600。
- **原生组件**：`MenuBarExtra`、`NSPanel`、`UNUserNotificationCenter`、`SMAppService`、GRDB。

### 4.2 技术栈

| 层 | 选择 | 说明 |
|---|---|---|
| UI | SwiftUI + AppKit | MenuBarExtra、NSPanel、自定义暗色主题 |
| 状态 | `@Observable` + Combine | 单一 Core，UI 只订阅 |
| 数据库 | SQLite + GRDB | WAL、显式迁移、易被 CLI 读取 |
| 通知 | UNUserNotificationCenter | 轮次结束、操作按钮 |
| 开机自启 | SMAppService | macOS 13+ |
| 全局快捷键 | KeyboardShortcuts / Carbon | `⌃⌥Space`、`⌘⇧N` |
| 本地 API | Unix socket + JSON-RPC | 0600、无端口 |
| CLI | Swift executable | 与 App 共享 `JingliCore` 库 |
| MCP | Swift / stdio JSON-RPC | **可选，v1.1**；CLI 已覆盖全部操作 |
| 测试 | Swift Testing / XCTest | 计时器与统计优先 |

---

## 5. 数据模型

| 表 | 关键字段 | 说明 |
|---|---|---|
| `project` | id, name, description, color, created_at, sort_order | 删除项目时把 `task.project_id` 置空 |
| `task` | id, title, project_id, lane(main/temporary), planned_date, note, done, created_at, completed_at, sort_order | 主线每天最多 4 |
| `day_plan` | date, started, started_at | 当天是否已开启 |
| `day_plan_task` | date, task_id, lane, selected_at | 草稿选择；开启后固化 |
| `focus_session` | id, session_date, started_at, ended_at, duration_sec, status, credited, focus_mode_on, focus_mode_owned | 一轮一条；**只保留今天**，跨天清空 |
| `focus_session_task` | session_id, task_id, share | 完成时按人数均分，`1/n` |
| `agent_event` | id, at, actor, action, payload, undo | Agent 审计（最近 50 条） |
| `setting` | key, value | 偏好 |

### 5.1 必须保真的行为

- 主线名额是**跨项目全局**的；完成后仍占当天的名额。
- 开启一天：选中的任务安排到今天；未选中的原今日任务回到未安排状态；完成状态、项目归属、**今日番茄记录**保留。
- 重置一天：不删除项目 / 任务，不恢复已完成任务，不清空**今日**累计番茄钟。
- 共享计时：中途加入的任务参与均分；提前完成或移出的任务不记这一轮；暂停 / 废弃不增加统计；同一轮不能因刷新 / 重启重复累计。
- 累计保留计算精度，只在显示时保留最多两位小数（三次 `1/3` 显示 1，不是 0.99）。
- 新任务在「开启一天」和项目内创建时默认不安排日期；今日页创建默认今天。
- **跨天清空**：未完成任务回到未安排；`focus_session` 删除；已完成任务保留完成状态，可在项目里查看，但不进历史统计。

### 5.2 统计口径（只算今天）

- **今日总番茄** = 今天完成的轮数（每轮 1 个，shared round 也只算 1）。
- **单任务番茄** = 今天 `sum(share)`，可能为 0.5 / 0.33 / 0.25。
- **今日专注分钟** = 今天完成轮数 × 25。
- **单任务参与时长** = 今天参与轮数 × 25；shared round 会在多个任务上重复计算，UI 上要和「今日总时长」分开标注。
- **今日完成任务** = `completed_at` 是今天的任务。
- **不做** 7 天 / 30 天窗口、legacy 历史、跨天累计；页面只展示今天。

### 5.3 迁移方案（只导当前状态）

- `workspace.v1` → `project` / `task` / `day_plan`。
- `liubai.pomodoro.v1.*` **不导入**；旧番茄历史直接忽略。
- `liubai.focus.v1` 进行中的计时：只有日期是今天才恢复，否则忽略。
- 建议先在 HTML 里加「导出 JSON」，再在 Mac 应用里做导入向导；导入后不保留历史。

迁移 JSON 建议结构：

```json
{
  "schema": "jingli.export.v1",
  "exportedAt": "2026-10-22T09:00:00Z",
  "workspace": { "version": 1, "projects": [], "tasks": [], "dayPlan": null },
  "focus": { "phase": "running", "taskIds": [], "remainingMs": 0, "endsAt": 0 }
}
```

### 5.4 番茄轮次状态机（v2 新增）

```text
idle ──选任务──▶ ready ──开始 + Focus On──▶ running ⇄ paused
                    │                         │
                    │                         ├─ 到时 ──▶ finished + Focus Off ──▶ 完成弹窗
                    │                         │              ├─ 开始休息 5 分钟 ──▶ break ──▶ idle
                    │                         │              ├─ 再来一轮 + Focus On ──▶ running
                    │                         │              └─ 回到清单 ──▶ idle
                    │                         └─ 废弃 + Focus Off ──▶ idle（不记账）
                    └─ 清空任务 ──▶ idle
```

规则：

- `finished` 是唯一写统计的状态；写入 `focus_session` + `focus_session_task`，`credited=1`，幂等。
- `finished` 时显示全局完成弹窗（独立 `NSPanel`，`level = .screenSaver`，`orderFrontRegardless()`），不要求主窗口存在，也不要求 App 是前台。
- 开始一轮调用 `Jingli Focus On`；`finished` / `abandoned` 仅在 `focus_mode_owned=1` 时调用 `Jingli Focus Off`；暂停保持勿扰，休息时关闭，再来一轮重新开启。
- 完成弹窗出现时，所有参与任务的控制回到「播放」；浮窗显示 `00:00 / 本轮结束`。
- 「开始休息 5 分钟」进入 `break`：独立 5 分钟倒计时，不产生番茄、不计入专注时长；结束用通知提醒，可跳过。
- 「再来一轮」复用本轮未完成任务集合；已完成 / 已移出的任务不自动加入。
- 「回到清单」或右上角 X 关闭弹窗，浮窗回到 idle；完成后「废弃本轮」应改成「关闭」或「结束本轮」，避免语义错误。
- App 重启时若处于 `finished` 但未记账，补记一次；若处于 `break`，按 `endsAt` 恢复。
- 休息轮次不进 `focus_session`；以后要统计休息，再加 `break_session`。

---

## 6. Agent / Skill 输入

把「输入支持 Agent」拆成两层：

1. **外部 Agent 通过 skill 把内容写进 App**（主路径）。
2. **App 内的输入框也能把自然语言交给 Agent**（辅助路径）。

### 6.1 三层结构

1. **CLI `jingli`**：主路径；人、脚本、Shortcuts、Raycast、Agent 都能用。
2. **SKILL.md**：教 Agent 何时调用、怎么确认、有哪些约束；放到 `~/.agents/skills/jingli/`。
3. **MCP server `jingli-mcp`（可选，v1.1）**：stdio JSON-RPC，给需要 MCP 的客户端提供 tools；v1 不实现，CLI 已覆盖全部操作。

### 6.2 CLI

```bash
jingli today --json
jingli task add "写周报" --project 工作 --lane main --date today
jingli day plan <id1> <id2> --dry-run
jingli day start
jingli focus start <id1> <id2>
jingli focus status --json
jingli focus stop
jingli stats --days 7 --json
```

约定：

- 所有命令支持 `--json`，便于 Agent 读取。
- 写操作返回变更后的状态摘要。
- App 未运行时，先 `open -b com.freedom-shen.jingli` 并等待 socket；超时给明确错误，不直接改数据库。
- 破坏性命令必须带 `--confirm`，否则拒绝执行。

### 6.3 MCP tools（可选，v1.1）

v1 不做 MCP；CLI 已覆盖以下全部操作。这里保留为 v1.1 的接口草案，需要时再加 `jingli-mcp` 薄翻译层。

- 读取：`get_today`、`list_projects`、`get_stats`
- 任务：`create_task`、`update_task`、`complete_task`、`reopen_task`
- 计划：`plan_day`（支持 `dry_run`）、`start_day`、`reset_day`
- 计时：`start_focus`、`focus_status`、`pause_focus`、`resume_focus`、`stop_focus`、`add_focus_task`、`remove_focus_task`
- 结束态：`finish_status`（本轮分摊）、`start_break`、`skip_break`、`next_round`

Tool 返回结构化 JSON + 一句人类可读摘要，方便 Agent 转述。

### 6.4 SKILL.md

建议内容：

- **触发**：`帮我排今天`、`记一下这件事`、`开始专注`、`今天精力怎么样`、`把这件事放到某个项目`。
- **约束**：主线最多 4 个；删除 / 重置 / 废弃本轮必须先问；`plan_day` 先 `dry_run` 再执行；每次操作后回读状态并给用户摘要。
- **结束态**：轮次完成后先读 `finish_status`，再按用户意愿调用 `start_break` / `next_round`；不要在未确认时自动开始下一轮。
- **示例流程**：
  1. 用户说「帮我把今天的主线排一下，优先季度复盘」。
  2. Agent 读 `jingli today --json` + 未排任务。
  3. 提议 3 主线 2 临时，先 `jingli day plan ... --dry-run` 校验。
  4. 用户确认后执行 `jingli day plan ...` + `jingli day start`。
  5. App 实时刷新，Agent 面板出现一条可撤销记录。
- **错误处理**：4 个主线已满、任务已完成、项目不存在、App 未启动，分别给出明确提示。

### 6.5 应用内输入

- **⌘K 命令条**：支持确定性语法（`写周报 明天 主线`、`开始专注 写周报`、`今天怎么样`）；不认识的输入显示「交给 Agent」，复制带上下文的 prompt。
- **Agent 活动面板**：最近 50 条操作，显示 actor / action / 时间，支持撤销（创建、修改、完成、排期；删除不提供撤销）。
- **设置 → Agent**：开关、token、复制 skill 安装命令；MCP 配置片段仅在启用可选 MCP 时显示。

### 6.6 安全与审计

- 只走 Unix socket / `127.0.0.1`；token 文件 0600；拒绝非本地来源。
- 破坏性操作需要 `confirm: true`；CLI（以及未来的 MCP）都做参数校验（4 个主线、任务已完成、项目不存在）。
- 所有 Agent 写操作进 `agent_event` 审计表；支持 `undo`。
- 不把任务内容发到任何远端；Agent 的模型调用发生在用户自己的 Agent 客户端。

---

## 7. 页面与交互范围

| 页面 | v1 内容 | Mac 增强 |
|---|---|---|
| **开启一天** | 按项目分组、勾选任务、主线 `n/4`、底部「开启一天」 | 默认启动页；`⌘↩` 开启 |
| **今日** | 主线 / 临时两区、卡片播放 / 完成 / 详情、完成态置灰划线 | 菜单栏快捷操作、通知 |
| **时钟结束** | 全局置顶弹窗：本轮分摊 `+1/n`、开始休息 5 分钟、再来一轮、回到清单；背景浮窗 `00:00`「本轮结束」 | 独立 `NSPanel`，覆盖全屏 / 所有 Space；系统通知同款操作；休息倒计时可在浮窗 / 菜单栏显示 |
| **项目** | 项目网格、项目详情、未分类任务 | 拖拽排序（可选） |
| **统计** | 3 张今日 KPI、今日专注记录；**不做 7 天图表** | 导出（可选）；无 Swift Charts |
| **浮窗** | 番茄钟、参与任务堆叠、添加 / 移出、废弃本轮；完成后显示 `00:00`「本轮结束」 | NSPanel 置顶、跨 Space、位置记忆 |
| **菜单栏** | 倒计时、暂停 / 继续、快速添加、打开主窗口 | MenuBarExtra |
| **设置** | 计时长度、通知、开机自启、数据备份、Agent、勿扰联动 | SMAppService、token 管理、快捷指令检查 |

设计约束：

- 不加侧边栏，保持设计稿的单页结构。
- 完成弹窗是全局窗口，不是主窗口内的 sheet；不要用 `NSAlert` 或 SwiftUI `.sheet`。
- 完成弹窗用自定义 modal，背景 dim + 轻微缩放，保持设计稿的安静感。
- 不建议强行上 Liquid Glass；保持纯黑卡片。浮窗 / 菜单可用系统材质做层次。
- 先做 design tokens（颜色、字号、圆角、间距、动效），再做页面。

### 7.1 全局完成弹窗（NSPanel）

- 独立 `NSPanel`，不挂在主 `WindowGroup` 上；主窗口关闭、App 在后台也能显示。
- `level = .screenSaver`（或 `.statusBar + 1`），`orderFrontRegardless()`，确保在最前面。
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]`，覆盖所有 Space 与全屏应用。
- `styleMask` 含 `.nonactivatingPanel`，`becomesKeyOnlyIfNeeded = true`：出现时不抢当前 App 的键盘焦点，点按钮时才成为 key。
- `isFloatingPanel = true`、`hidesOnDeactivate = false`，切到别的 App 也不消失。
- 自定义 `NSView` 重写 `acceptsFirstMouse(for:)` 返回 `true`，保证 App 不在前台时第一次点击就能按到按钮。
- 显示在鼠标所在屏幕并居中；多显示器只出现一次。
- 锁屏 / 睡眠时不强推；唤醒后补显示，并同时发系统通知兜底。
- 可选：30 秒无操作后降到普通浮窗层级或缩到右下角，避免长期挡住工作。
- 验收覆盖：主窗口关闭、App 后台、全屏视频 / IDE、多 Space、Stage Manager。

### 7.2 勿扰模式联动（Shortcuts）

**产品行为：**

- 开始一轮番茄 → 自动开启「勿扰模式」。
- 暂停 → 保持勿扰。
- 完成 / 废弃本轮 → 自动关闭勿扰。
- 「开始休息 5 分钟」→ 关闭勿扰，休息时恢复通知。
- 「再来一轮」→ 再次开启勿扰。
- 退出 App → 若本轮由应用开启勿扰，退出前关闭；下次启动若轮次仍活跃，再重新开启。

**技术方案：**

- macOS 11+ 没有公开 API 直接设置 Focus；使用 Shortcuts 的「设置专注模式」动作，应用通过 `/usr/bin/shortcuts run "<快捷指令名>"` 调用。
- 首次使用在「设置 → 勿扰联动」引导创建两个快捷指令：
  - `Jingli Focus On`：Set Focus → 勿扰模式 → 打开 → 直到关闭。
  - `Jingli Focus Off`：Set Focus → 勿扰模式 → 关闭。
- 应用启动时用 `shortcuts list` 检查两个名字；缺失时功能降级为提示，不阻塞计时。
- 第一次调用会触发 macOS 的自动化权限弹窗；拒绝后不再重复弹，只在设置里显示「未授权」。
- Focus On / Off 用串行队列异步执行，避免快速开始 / 结束时顺序错乱；不阻塞计时开始。
- 不调用私有 API，不做 Control Center UI 脚本，避免 macOS 升级失效。

**已有 Focus 的处理：**

- 开始前用 `INFocusStatusCenter` 读取系统是否已处于某个 Focus（需要用户授权 + Focus Status 权限）；如果已经开启，默认不接管：不开启勿扰，结束时也不关闭。
- 读不到授权 / 读取失败：按「未开启」处理，并在设置里提示「无法判断当前 Focus」。
- 设置项可选「总是接管」：开始前先关闭其他 Focus，再开启勿扰；结束时关闭勿扰。这个选项要明确告知会改变用户原有的 Focus。

**状态与恢复：**

- `focus_session.focus_mode_on`：本轮是否由应用开启了勿扰。
- `focus_session.focus_mode_owned`：是否由应用负责关闭（开始前已有 Focus → false）。
- App 启动：没有活跃轮次但 `focus_mode_owned=1` → 补一次 `Focus Off`；有活跃轮次且设置为开启 → 补一次 `Focus On`。
- App 正常退出：`applicationWillTerminate` 同步调用 `Focus Off`，最多等 1 秒。
- App 崩溃：下次启动按上面的规则补关闭。
- 用户手动关掉勿扰：不强制重开；把本轮 `focus_mode_owned` 置 false，结束时不再调用 `Focus Off`。

**设置项：**

- 开始番茄时自动开启勿扰（默认开，首次需配置快捷指令）
- 结束时自动关闭（默认开）
- 开始时已有其他 Focus：保留 / 总是接管（默认保留）
- 休息期间保持勿扰（默认关）
- 快捷指令名称（默认 `Jingli Focus On` / `Jingli Focus Off`，可自定义）
- 「测试」按钮：分别运行 On / Off，确认权限和快捷指令可用

**验收：**

- 配置快捷指令后：开始 → 控制中心显示勿扰；完成 / 废弃 → 退出。
- 暂停不退出；休息退出；再来一轮重新进入。
- 快速连续开始 / 结束，最终勿扰状态与最后一次操作一致（串行队列）。
- 未配置快捷指令：计时正常，只提示一次。
- 开始前已有「工作」Focus：默认不接管，结束时也不关闭。
- 强制退出 App 后重新打开：不会把勿扰留在开启状态。

---

## 8. 路线图

| 阶段 | 时间 | 交付 | 验收 |
|---|---|---|---|
| **Phase 0** | 2–3 天 | 定口径、设计 token、HTML 导出、工程骨架、测试骨架（`self-test.sh` / 测试库 / fake clock / `--snapshot` 模式） | 一页 PRD + 迁移 JSON 样例 + 空页面导航能跑 + `self-test --fast` 跑通空测试 + 1 个 snapshot case |
| **Phase 1** | 5–7 天 | 原生壳 + SQLite + 任务 / 项目 CRUD + 今日页 + 计时器 + 菜单栏 + 浮窗 + 完成弹窗 + 勿扰联动 + 通知 | 能完整过一天：建任务 → 排期 → 开始 / 暂停 / 继续 → 完成 → 查看分摊 → 休息 / 再来一轮；开始 / 结束正确切换勿扰；重启 / 睡眠后计时准确；浮窗跨 Space 置顶 |
| **Phase 2** | 4–6 天 | 开启一天（按项目分组）+ 重置 + 项目页 + 今日统计页 + 设置 + 导入（只导任务/项目） | 功能对齐 HTML + PDF（不含 7 天图表）；今日统计；任务/项目导入 |
| **Phase 3** | 4–5 天 | Agent socket + CLI + SKILL.md + 审计 / 撤销 + ⌘K | 新开一个 Agent 会话，说「帮我排今天的主线」能端到端完成；删除类操作无确认会被拒绝 |
| **Phase 4** | 2–3 天 | 完整一天 + 跨天重置、性能 / 可访问性 / 图标 / 打包 / 备份 | 完整一天无数据丢失；跨天清空正确；内存 < 150MB；计时误差 < 1s |
| **v1.1（可选）** | 1 周 | 今日精力 check-in、MCP（可选）、英文（可选） | 能记录今天的精力状态；不做历史复盘 |

按每天投入 2–3 小时算，v1.0 大约 **2–3 周**。

### 8.1 验收标准

**Phase 1**

- [ ] 新建 / 编辑 / 删除任务与项目
- [ ] 今日页主线 / 临时分区正确
- [ ] 开始、暂停、继续、完成、废弃本轮
- [ ] App 重启后计时恢复
- [ ] 睡眠唤醒后计时正确
- [ ] 菜单栏显示倒计时
- [ ] 浮窗置顶、跨 Space、位置记忆
- [ ] 轮次结束通知 + 声音，通知操作与完成弹窗一致
- [ ] 完成弹窗显示每个任务 `+1/n`，可「开始休息 5 分钟」「再来一轮」「回到清单」
- [ ] 完成弹窗在全局最前端：主窗口关闭、App 后台、全屏应用、多 Space 下都能出现
- [ ] 开始一轮自动开启勿扰；完成 / 废弃自动关闭；暂停保持；休息关闭；再来一轮重新开启
- [ ] 未配置快捷指令 / 自动化权限被拒绝时，计时不阻塞，只提示一次
- [ ] 开始前已有其他 Focus 时默认不接管，结束时也不关闭
- [ ] App 强制退出后重新打开，不会把勿扰留在开启状态
- [ ] 休息倒计时可跳过，且不计入番茄统计
- [ ] `scripts/self-test.sh --fast` 通过（unit + UI smoke + snapshots）
- [ ] 核心 snapshot case 通过：day-start / today-running / completion-panel / stats

**Phase 2**

- [ ] 开启一天按项目分组，主线全局最多 4
- [ ] 重置一天符合规格
- [ ] 今日统计 KPI + 今日记录（无 7 天图表）
- [ ] 任务 / 项目导入（不导旧番茄历史）
- [ ] 设置项生效

**Phase 3**

- [ ] CLI 全部命令可用；`--json` 输出稳定
- [ ] Skill 能完成「读状态 → 提议 → dry-run → 执行 → 回读」
- [ ] 删除 / 重置无确认被拒绝
- [ ] Agent 操作可审计、可撤销
- [ ] MCP（可选）：v1.1 再接，不影响 Phase 3 验收

**Phase 4**

- [ ] 完整一天真实使用
- [ ] 跨天重置：未完成任务回未安排、今日番茄清空、已完成保留
- [ ] 无数据丢失
- [ ] 内存 < 150MB，空闲 CPU ≈ 0
- [ ] 计时误差 < 1s
- [ ] 备份 / 恢复演练通过

### 8.2 完整测试还缺什么

现在文档里只有「验收标准」，还缺五块：**可测试性架构、测试夹具、环境矩阵、自动化、发布门槛**。没有这五块，回归只能靠手点，越到后面越不敢改。

#### 8.2.1 可测试性（先补架构）

- `Clock` 注入：真实 / 测试时钟；计时测试直接推进时间，不靠 `sleep`。
- `FocusController`：真实 Shortcuts / Mock；勿扰状态机不依赖 macOS。
- `ShortcutRunner`：执行 `shortcuts run` / Mock 超时、拒绝、未安装。
- `NotificationScheduler`：真实 `UNUserNotificationCenter` / Mock；测试通知动作。
- `WorkspaceObserver`：睡眠、唤醒、屏幕变化、App 激活；测试恢复逻辑。
- `IDGenerator`：UUID / 固定序列；测试幂等。
- UI 测试启动参数：`-ui-testing`、`-test-db <path>`、`-fake-clock`、`-disable-animations`、`-skip-onboarding`。
- 测试库：临时 SQLite / 内存库；每个测试独立，绝不碰真实数据。

#### 8.2.2 测试夹具

- HTML 导出：空工作区、Demo 数据、进行中、暂停、已完成未记账（不导旧番茄历史）。
- 任务边界：160 字标题、2000 字备注、emoji、中英混排、特殊字符。
- 计划边界：0 / 1 / 4 / 5 个主线、跨项目、已完成仍占名额、未排日期、过期临时任务。
- 数据量：100 项目 / 10,000 任务 / 今日 50 条番茄记录。
- 异常：损坏 JSON、重复 ID、缺失项目、非法日期、负时长。
- 数据库：空库、旧 schema、WAL 锁、只读、导入中断。
- 快照：4 个主页面 + 完成弹窗的基准图。

#### 8.2.3 测试矩阵

| 模块 | 必须覆盖 |
|---|---|
| 计时器 | 1/2/3/4 人均分；中途加入 / 移出；提前完成；暂停 / 继续；废弃；到时；重启；睡眠唤醒；时区 / DST / 手动改时钟；跨午夜；重复记账 |
| 开启一天 | 主线全局 4 个上限；取消 / 重选；草稿保存；开始后未选任务回未安排；重置；完成仍占名额；跨天重置 |
| 统计 | 今日总番茄整数；单任务份额；今日总时长 vs 参与时长；四舍五入；跨午夜归属（只影响今天） |
| 勿扰 | 快捷指令缺失 / 重命名；自动化拒绝；已有 Focus；手动关闭；休息 / 再来一轮；崩溃 / 重启；串行队列；调用延迟 |
| 全局弹窗 | 主窗口关闭；App 后台；全屏；所有 Space；Stage Manager；多显示器；第一次点击；键盘焦点；Esc；屏幕共享 / 录制 |
| 通知 | 允许 / 拒绝；前台 / 后台；通知动作；勿扰开启时系统通知被静音，但完成弹窗仍出现；声音 |
| Agent | CLI JSON schema；dry-run；4 主线绕过；删除确认；审计 / 撤销；并发 UI + Agent；App 未运行；socket 失效；token 轮换；恶意输入；MCP（可选）不影响 v1 |
| 迁移 | 任务 / 项目导入；重复导入；中断导入；旧 schema 升级；备份 / 恢复 |
| UI | 1440×900 基准截图；1280 / 2560 宽度；4 列 / 窄屏；长文本截断；空状态；键盘导航；VoiceOver；Reduce Motion；高对比度；刘海菜单栏 |
| 性能 | 空闲 CPU；计时中 CPU；内存；10k 任务；启动时间；8 小时连续计时；跨天重置 |
| 发布 | clean build；签名；notarize；首次启动；v1.0 → v1.1 升级；卸载残留；数据清理 |

#### 8.2.4 环境矩阵

- macOS 15.x / macOS 26.x（deployment target 15 时两个都测）
- Apple Silicon / Intel（如有 Intel 机器）
- 单屏 / 多屏 / 不同缩放 / 带刘海
- 全屏应用 / 多 Space / Stage Manager
- 通知权限：允许 / 拒绝 / 勿扰
- Shortcuts：已创建 / 缺失 / 重命名 / 自动化拒绝
- Focus：无 / 勿扰 / 工作 / 睡眠
- 电源：电池 / 电源适配器；睡眠 / 唤醒 / 锁屏
- 网络：离线（确认无网络依赖）
- 语言 / 时区：中文（v1）/ 英文（v1.1）；东八区 / 跨时区；DST
- 数据：空 / 正常 / 大数据 / 损坏

#### 8.2.5 自动化与 CI

- `scripts/self-test.sh --fast`：单元 + 集成 + CLI contract + UI smoke + lint（详见 8.3）。
- `xcodebuild test`：JingliCore、CLI；UI 测试单独 job（较慢）；MCP 可选，不进 PR 门禁。
- 快照测试：4 个主页面 + 完成弹窗，基准图存 `Tests/Snapshots/`。
- 覆盖率：建议 Core ≥ 80%、整体 ≥ 60%；计时 / 统计 / 迁移必须高覆盖。
- CI：macOS runner；PR 跑 `--fast`；夜间跑 `--full` + 性能；tag 跑 release build。
- 测试报告：JUnit / xcresult；失败自动附截图和日志。

#### 8.2.6 发布门槛

- 完整一天真实使用（Phase 4 已有）+ 一次跨天重置。
- 当天至少 4 轮番茄；至少 2 次共享轮次；至少 1 次中途加入 / 移出。
- 至少 1 次睡眠唤醒、1 次强制退出、1 次勿扰手动关闭。
- P0（数据丢失 / 崩溃 / 计时错误 / 勿扰残留）为零；P1 有明确 workaround。
- 备份 / 恢复演练：导出 → 删除库 → 导入 → 数据一致。
- 发布前 checklist：签名、版本号、CHANGELOG、迁移、回滚方案。

#### 8.2.7 还缺的测试文档

- `docs/test-plan.md`：范围、策略、环境、退出标准。
- `docs/test-cases.md`：按模块列 case，带前置条件和预期。
- `docs/qa-checklist.md`：每次发版手动过一遍。
- `docs/manual-test.md`：不可自动化项的手工步骤与证据要求。
- `docs/known-unautomatable.md`：不可自动化边界清单。
- `Tests/Fixtures/`：迁移 JSON、边界任务、损坏数据。
- `Tests/Snapshots/`：页面基准图。

### 8.3 自我测试闭环（脚本 + UI 自动化）

目标：改完一处代码，跑一条命令就知道「有没有坏」；失败时输出机器可读的结果、截图和日志，Agent 可以直接读、修、再跑。

#### 8.3.1 闭环

```text
改代码
  ↓
scripts/self-test.sh --fast
  ├─ build
  ├─ unit（JingliCore / CLI）
  ├─ integration（临时 DB / socket / 迁移）
  ├─ UI smoke（XCUITest）
  ├─ snapshots（4 页面 + 完成弹窗）
  └─ lint / secret scan
  ↓
artifacts/<timestamp>/report.json + summary.md
  ↓
失败 → 读失败用例 + 截图 + 日志 → 修复 → 重跑
  ↓
通过 → PR → CI --full → merge
```

目标时间：`--fast` < 3 分钟；`--full` < 15 分钟；夜间可以跑 30 分钟以上。

#### 8.3.2 脚本清单

| 脚本 | 作用 | 输出 |
|---|---|---|
| `scripts/self-test.sh` | 总入口；`--fast` / `--full` / `--ui` / `--agent` / `--snapshot` / `--json` | `artifacts/<ts>/report.json` |
| `scripts/test-unit.sh` | `swift test` + `xcodebuild test` 单元 | xcresult |
| `scripts/test-integration.sh` | 临时 DB、迁移、CLI、socket | xcresult / JSON |
| `scripts/test-ui.sh` | XCUITest，按 `-only-testing:JingliUITests` | xcresult + 截图 |
| `scripts/test-agent.sh` | CLI JSON schema、dry-run、confirm；MCP 可选 | JSON |
| `scripts/test-snapshot.sh` | 截图对比；`--update` 更新基线 | diff 图 + 报告 |
| `scripts/test-performance.sh` | XCTest metrics：启动、内存、CPU、计时漂移 | JSON |
| `scripts/doctor.sh` | 环境检查：Xcode、Shortcuts、权限、屏幕 | 终端报告 |
| `scripts/seed-fixtures.sh` | 生成测试库 / 夹具 | `.sqlite` / JSON |
| `scripts/report.sh` | xcresult → JSON / Markdown | `summary.md` |
| `scripts/ci.sh` | CI 入口，按 PR / nightly / tag 选择模式 | CI artifacts |

`Makefile` 提供短命令：

```makefile
test:        scripts/self-test.sh --fast
test-full:   scripts/self-test.sh --full
test-ui:     scripts/self-test.sh --ui
snapshot:    scripts/self-test.sh --snapshot
snapshot-update: scripts/test-snapshot.sh --update
doctor:      scripts/doctor.sh
```

#### 8.3.3 UI 自动化（XCUITest）

> UI 主验证改成**状态驱动截图测试**（见 8.5）；这里只保留 3–5 条交互 smoke，验证按钮接线。下面的 16 条用例可以复用为截图状态。

**测试 target：** `App/JingliUITests`。

**启动参数 / 环境变量：**

- `-ui-testing`：启用测试模式，隐藏 onboarding、禁用真实通知。
- `-test-db /tmp/jingli-ui-<uuid>.sqlite`：独立测试库。
- `-fixture empty|day-start|today|stats|finished`：预置数据（不预置历史）。
- `-fake-clock 2026-10-22T09:00:00+08:00`：可控时间。
- `-disable-animations`：关闭动效，减少 flaky。
- `-window-size 1440x900`：固定窗口尺寸，便于截图。
- `-skip-onboarding`：跳过首次启动引导。
- `-mock-focus`：勿扰走 Mock，不调用真实 Shortcuts。
- `-mock-notifications`：通知走 Mock，不弹系统横幅。

**Accessibility Identifier（所有可交互元素必须有）：**

`main-window`、`day-start-button`、`task-card-<id>`、`task-play-<id>`、`task-done-<id>`、`task-detail-<id>`、`focus-dock`、`focus-clock`、`completion-panel`、`completion-row-<id>`、`break-button`、`next-round-button`、`back-to-list-button`、`menu-bar-extra`、`project-card-<id>`、`stats-kpi`。

**核心 UI 用例：**

| 编号 | 场景 | 断言 |
|---|---|---|
| UI-01 | 首次启动 / 空状态 | 显示空状态，新建任务可用 |
| UI-02 | 开启一天：选 3 主线 + 2 临时 | 主线计数 `3/4`，底部按钮可用 |
| UI-03 | 选第 5 个主线 | 被拒绝，提示最多 4 个 |
| UI-04 | 开始一天 | 今日页出现 5 个任务，未选任务回未安排 |
| UI-05 | 单任务番茄：开始 → 假时钟到 0 | 完成弹窗出现，`+1` |
| UI-06 | 两任务共享：开始 → 到 0 | 每行 `+0.5`，总计 1 |
| UI-07 | 暂停 / 继续 / 废弃 | 状态正确，废弃不记账 |
| UI-08 | 完成弹窗：休息 5 分钟 | 浮窗 `05:00`，主页面可操作 |
| UI-09 | 再来一轮 | 复用未完成任务，重新计时 |
| UI-10 | 完成任务 | 卡片置灰划线，仍占主线名额 |
| UI-11 | 重置一天 | 回到开启一天，任务保留 |
| UI-12 | 项目删除 | 任务进未分类 |
| UI-13 | 统计页（种子数据） | 今日 KPI、今日记录；无 7 天图 |
| UI-14 | 菜单栏 | 显示倒计时，暂停 / 继续 |
| UI-15 | 完成弹窗全局（测试模式） | 独立窗口存在；真实置顶手工测 |
| UI-16 | 勿扰 Mock | start 调用 On，finish 调用 Off |
| UI-17 | 跨天重置 | 未完成任务回未安排；今日番茄清空；已完成保留 |

**UI 自动化的边界：**

- 真正的「跨 App 最前端」、多显示器、所有 Space、Stage Manager、真实通知、真实 Focus，XCUITest 无法完整覆盖；用 Mock + 手工矩阵补。
- 菜单栏 extra 的 accessibility 容易 flaky；提供测试专用 `jingli://` URL scheme 或菜单命令触发。
- 失败先重跑一次确认是否 flaky；flaky 用例隔离并建 issue，不长期静默重试。

#### 8.3.4 快照与视觉回归

> 完整截图方案、状态矩阵、diff 工具与基线策略见 8.5。

- 固定 1440×900、深色外观、关闭动画、隐藏光标。
- 基准图存 `Tests/Snapshots/<screen>@2x.png`。
- 像素差异阈值 0.5%；超过阈值输出 diff 图。
- `--update-snapshots` 只在确认设计变更时使用，并随 commit 提交基准图。
- 失败时自动附加：当前截图、基线图、diff 图、窗口尺寸、缩放比例。

#### 8.3.5 报告与 Agent 闭环

`report.json` 结构：

```json
{
  "status": "failed",
  "mode": "fast",
  "duration_ms": 142000,
  "suites": [
    { "name": "unit", "passed": 42, "failed": 1 },
    { "name": "ui", "passed": 8, "failed": 0 }
  ],
  "failures": [
    {
      "test": "TimerTests.sharedSplit",
      "message": "expected 0.5, got 0.333",
      "file": "Tests/TimerTests.swift:88",
      "artifacts": ["artifacts/.../failure.png", "artifacts/.../app.log"]
    }
  ],
  "artifacts_dir": "artifacts/2026-10-22T09-00-00"
}
```

- 退出码：`0` 通过，`1` 测试失败，`2` 环境 / 配置错误。
- `summary.md`：一屏内看完，列 top failures、截图链接、复现命令。
- Agent 循环：`self-test --fast` → 读 `report.json` → 修复 → 重跑；PR 前跑 `--full`，结果贴进 PR。
- 写进 `AGENTS.md`：「改完代码必须跑 `scripts/self-test.sh --fast`；提交前 `--full`。」

#### 8.3.6 CI

- PR：`scripts/self-test.sh --fast` + UI smoke。
- Nightly：`--full` + 性能 + 快照 + 假时钟跨天重置模拟。
- Tag：release build + notarize + clean-user smoke。
- macOS runner：`macos-26`；缓存 SPM；上传 `artifacts/`。
- 测试报告：xcresult + JUnit；PR 里自动贴摘要。

#### 8.3.7 运行期自检

- `jingli doctor`：DB integrity、schema 版本、孤儿 session、残留勿扰、重复记账、备份年龄。
- `jingli doctor --json`：给 Agent 读。
- App 启动时轻量自检：残留勿扰自动清理；DB 损坏进入恢复流程。
- `scripts/doctor.sh` 只检查开发环境，不碰用户数据。

#### 8.3.8 还差什么（自测闭环 checklist）

- [ ] 所有可交互元素加 `accessibilityIdentifier`
- [ ] `JingliUITests` target + 16 条核心用例
- [ ] Fake clock + Mock Focus / Notification / Shortcut
- [ ] 临时测试库 + `Tests/Fixtures/` 夹具
- [ ] `Tests/Snapshots/` 基准图
- [ ] `scripts/self-test.sh` + `report.json`
- [ ] CI 的 PR / nightly / tag 三档
- [ ] `AGENTS.md` 写明自测命令

### 8.4 哪些没法完全自闭环

先给结论：**系统级 Mac App 不存在 100% 自闭环**。目标不是消灭手工测试，而是把「不可自动化」压到一张明确的清单，并用 **Mock + 合同测试 + 手工 gate + dogfood** 兜底。

#### 8.4.1 自闭环成熟度

| 层级 | 含义 | 适用 |
|---|---|---|
| **L3** | Agent 读报告 → 自动修 → 重跑 | 单元、集成、CLI、大部分 UI |
| **L2** | 自动跑 + 机器可读报告，但修复靠人 | 快照、性能、迁移、崩溃恢复 |
| **L1** | 脚本辅助，关键动作仍需人 | 签名 / 公证、升级、磁盘满、DB 损坏 |
| **L0** | 只能手工，留证据 | 全局窗口、真实 Focus、通知中心、多显示器、真机完整一天 |

#### 8.4.2 不可自动化的边界（必须手工）

| 类别 | 具体项 | 为什么不能自闭环 | 最佳近似 | 频率 |
|---|---|---|---|---|
| 全局窗口 | 真正跨 App 最前端、全屏、所有 Space、Stage Manager、屏幕共享 / 录制 | XCUITest 只能验证窗口存在和属性，验证不了系统合成的 Z-order | 断言 `level` / `collectionBehavior` / `isVisible` + 手工录屏 | 每个 release |
| 系统勿扰 | 真实 Focus 开关、已有 Focus、权限弹窗、Shortcuts 被重命名 / 删除 | Shortcuts 和 TCC 是系统 UI，不可编程 | Mock `FocusController` + 真实 Shortcuts 手工 smoke | 每个 release + 每次 macOS 升级 |
| 通知 | 真实通知中心、横幅、操作按钮、勿扰下静音 | 系统通知 UI 不可控 | Mock `NotificationScheduler` + 手工发一条真通知 | 每个 release |
| 菜单栏 | 刘海、多菜单项、系统深浅色、Stage Manager | XCUITest 对 status item 支持有限且 flaky | 测试专用 `jingli://` 命令 + 手工 | 每个 release |
| 睡眠 / 唤醒 / 锁屏 | 真实电源事件、锁屏后恢复 | CI VM 不能可靠触发 | Mock `WorkspaceObserver` + 本地 `pmset sleepnow` 手工 | 每个 release |
| 多显示器 / Space | 物理显示器、缩放、系统合成 | 无法在 CI 创建可靠虚拟显示器 | 手工矩阵 + 录屏 | 每个 release |
| 签名 / 公证 / 首次启动 | Gatekeeper、quarantine、干净机器 | 需要干净 macOS 用户 / VM | `codesign` / `notarytool` / `spctl` 自动 + 干净 VM 手工 | 每个 release |
| 升级 / 卸载 | 旧版本 → 新版本、残留文件 | 依赖真实用户目录 | 安装旧版 → 新版脚本 + 手工检查 | 每个 minor release |
| macOS 升级 | 新系统行为变化 | 无法预测 | 环境矩阵手工跑 | 每次大版本 |
| 真实完整一天 | 真实节奏、疲劳、注意力；跨天重置 | 无法模拟 | dogfood 一天 + 跨天重置检查 | 每个 v1.0 |
| Agent / LLM 行为 | 模型选择、工具调用不确定性 | 不能断言唯一输出 | 合同测试 + 假 Agent + golden prompt eval（N 次阈值）+ 手工验收 | 每个 Phase 3 |
| 视觉 / 手感 | 动画、拖拽、字体渲染、毛玻璃 | 截图抓不到手感 | 快照 + 录屏 + 设计 review | 每个 UI 变更 |
| 辅助功能 / 输入法 | VoiceOver 体验、中文 IME 组合 | 自动 AX audit 只能查标签 | Accessibility Inspector + 手工 | 每个 release |
| 性能 / 电量 | 真实电池、热、功耗 | XCTest metrics 测不到整机功耗 | `powermetrics` + 手工 | 每个 release |

#### 8.4.3 可以补成自动化的部分（目前仍是手工）

| 项目 | 现在 | 可以怎么补 |
|---|---|---|
| 崩溃恢复 | 手点 | `kill -9` → 重启 → 检查 DB / 计时 / 勿扰状态，脚本化 |
| 升级迁移 | 手点 | 安装旧 build → 覆盖新 build → 检查 schema / 数据，脚本化 |
| 磁盘满 | 手点 | `hdiutil` 建小容量 APFS 卷，写入失败路径测试 |
| DB 损坏 | 手点 | 截断 / 改写 SQLite 文件，验证恢复流程 |
| 菜单栏 | 手点 | 测试专用 `jingli://` URL scheme / 菜单命令，UI 测试触发 |
| 全屏 | 手点 | 测试 host 窗口调用 `toggleFullScreen`，UI 测试验证 |
| 本地化 | 手点 | 中 / 英快照 + 文本膨胀检查 |
| 签名 | 手点 | `codesign` / `notarytool` / `spctl --assess` 进 CI |

#### 8.4.4 手工 gate 怎么做

- `docs/manual-test.md`：按 release 列步骤、预期、证据要求。
- `docs/known-unautomatable.md`：维护「不可自动化清单」，新增系统依赖时更新。
- `scripts/manual-check.sh`：不能替你点，但能记录结果到 `artifacts/manual/<version>/<date>.json`。
- `scripts/release-gate.sh`：检查 P0 手工项是否全部通过、证据是否齐全；不通过则拒绝打 tag。
- 证据：截图 / 录屏 / 日志 / `powermetrics` 输出，按版本归档。
- 频率：每个 release、每次 macOS 大版本、每次改 DND / 通知 / 全局窗口。

#### 8.4.5 边界原则

- Mock 只能证明「我们调用正确」，不能证明「系统真的这么表现」；每个 mock 边界至少保留一条真实 smoke。
- 不能自动化的项不要假装自动；写进 gate，留下证据。
- 每次 macOS 升级重跑手工矩阵；系统行为变化是最大风险。
- Dogfood 是最终测试：**完整一天 + 跨天重置** > 100 条 UI 用例。

#### 8.4.6 还缺的文档 / 脚本

- `docs/manual-test.md`
- `docs/known-unautomatable.md`
- `scripts/manual-check.sh`
- `scripts/release-gate.sh`
- `artifacts/manual/`（gitignore）

### 8.5 UI 截图测试闭环（主方案）

结论：UI 不做全交互自动化，改成 **状态驱动截图 + 像素比对 + 差异报告**。逻辑由单元 / 集成测试保证，截图保证「每个状态长得对」。这样既闭环，又不会陷入 XCUITest 的 flaky。

#### 8.5.1 闭环

```text
改代码
  ↓
scripts/snapshot.sh
  ├─ 逐个 case：启动 App → 注入 fixture / state → 固定窗口 1440×900 → 截图
  ├─ 与 Tests/Snapshots/<case>.png 比对（Swift diff 工具）
  ├─ 生成 diff 图 + report.json
  └─ 超过阈值 → 非 0 退出
  ↓
Agent 读 report.json → 修 → 重跑
  ↓
确认是设计变更 → scripts/snapshot.sh --update --case <case> → 单独 commit 基线
```

#### 8.5.2 截图矩阵（状态驱动）

下面列了 22 个候选；先做 12–15 个核心 case，稳定后再扩。

| case | 状态 | 重点 |
|---|---|---|
| `day-start-empty` | 空工作区 | 空状态、按钮可用 |
| `day-start-selected` | 3 主线 + 2 临时选中 | `3/4`、底部按钮 |
| `day-start-max` | 4 主线 + 5 个未选 | 第 5 个不可选 / 提示 |
| `today-running-2` | 2 任务共享，12:41 | 卡片、浮窗、参与任务堆叠 |
| `today-paused` | 暂停态 | 暂停图标、浮窗状态 |
| `today-finished` | 00:00 本轮结束 | 浮窗、卡片控制复位 |
| `completion-panel-2` | 2 任务各 `+0.5` | 全局弹窗布局、按钮 |
| `completion-panel-1` | 1 任务 `+1` | 单任务分摊 |
| `break-running` | 05:00 休息 | 浮窗 / 菜单栏状态 |
| `today-done` | 部分任务完成 | 置灰、划线、仍占主线名额 |
| `today-long-text` | 160 字标题 + 2000 字备注 | 截断、换行、详情弹窗 |
| `today-many` | 4 主线 + 8 临时 | 4 列 / 换行 / 滚动 |
| `projects` | 5 个项目 + 未分类 | 网格、颜色、任务数 |
| `project-detail` | 项目详情 | 任务列表、空状态 |
| `stats-data` | 今日数据 | 今日 KPI、今日记录 |
| `stats-empty` | 无数据 | 空状态 |
| `settings` | 设置页 | 勿扰、Agent、数据 |
| `dialog-task` | 新建 / 编辑任务 | 表单、日期快捷键 |
| `dialog-project` | 新建项目 | 颜色选择 |
| `dialog-confirm` | 删除确认 | 危险按钮 |
| `menu-bar` | 菜单栏面板 | 倒计时、快捷操作 |
| `narrow-1280` | 1280 宽 | 列数、截断 |

#### 8.5.3 截图模式怎么实现

推荐 **App 内建 `--snapshot` 模式**，而不是用系统截图工具：

```bash
Jingli.app/Contents/MacOS/Jingli \
  --snapshot \
  --case today-running-2 \
  --fixture Tests/Fixtures/today-running-2.json \
  --size 1440x900 \
  --scale 1 \
  --locale zh-Hans \
  --timezone Asia/Shanghai \
  --fake-clock 2026-10-22T09:00:00+08:00 \
  --disable-animations \
  --out artifacts/snapshot/today-running-2.png
```

实现要点：

- SwiftUI 视图包进 `NSHostingView`，`layoutSubtreeIfNeeded()` 后用 `bitmapImageRepForCachingDisplay(in:)` + `cacheDisplay(in:to:)` 抓自己的窗口内容；**不需要屏幕录制权限**，也不会被其他窗口挡住。
- 完成弹窗 / 浮窗用独立的 `NSPanel` contentView 抓图，不依赖它是否真的在最前面（真置顶仍走 8.4 手工）。
- 菜单栏面板直接渲染 popover 的 contentView，不抓系统 status item。
- 如果只需要组件级截图，用 `ImageRenderer` 更快；但 `NSVisualEffectView` / 材质 / AppKit 控件可能不准，整页仍用 `cacheDisplay`。
- 固定环境：深色外观、隐藏光标、关闭动画、固定 locale / timezone / 时钟、禁用随机 ID（fixture 固定 UUID）。
- 不抓窗口阴影、标题栏、系统菜单；这些不属于内容回归。

#### 8.5.4 比对与基线

- 自写 Swift 小工具 `jingli-snapshot-diff`：读两张 PNG，逐像素 RGBA 比较，输出 mismatch ratio、diff 图、`metrics.json`；不引入 ImageMagick / pixelmatch 依赖。
- 判定：单像素差 > 2/255 记为差异；总差异像素 ≤ 0.3% 通过；单 case 可覆盖阈值。
- 基线：`Tests/Snapshots/<case>.png`；1x（1440×900）控制仓库体积，需要看细节时本地 `--scale 2` 生成，不进基线。
- 跨 macOS 版本：字体 / 控件渲染会变；基线按主版本分目录（`Tests/Snapshots/macos-26/`），或者本机跑全量、CI 只跑 3 个 smoke case。
- 更新基线必须单独 commit：`test(snapshot): update completion-panel-2 baseline`，PR 说明是设计变更还是修 bug。
- 失败产物：`artifacts/snapshot/<case>/current.png`、`baseline.png`、`diff.png`、`metrics.json`。

#### 8.5.5 脚本与命令

```bash
scripts/snapshot.sh                          # 全量截图 + 比对
scripts/snapshot.sh --case today-running-2   # 单 case
scripts/snapshot.sh --update --case completion-panel-2
scripts/snapshot.sh --report artifacts/snapshot/report.json
scripts/self-test.sh --fast                  # 包含核心 snapshot
scripts/design-compare.sh today-running-2    # App 截图 vs PDF 设计稿并排
```

`report.json` 示例：

```json
{
  "status": "failed",
  "cases": [
    {
      "case": "today-running-2",
      "mismatch": 0.0081,
      "threshold": 0.003,
      "current": "artifacts/snapshot/today-running-2/current.png",
      "baseline": "Tests/Snapshots/macos-26/today-running-2.png",
      "diff": "artifacts/snapshot/today-running-2/diff.png"
    }
  ]
}
```

#### 8.5.6 和 XCUITest / 单元测试的分工

- **截图测试**：所有「长得对不对」——布局、颜色、文案、空状态、长文本、完成弹窗、统计图。
- **单元 / 集成测试**：所有「逻辑对不对」——计时、分摊、主线 4 个、重置、迁移。
- **XCUITest**：只保留 3–5 条交互 smoke——启动 → 开始一天 → 开始计时 → 到点 → 完成弹窗 → 回到清单，验证按钮接线。
- **手工 gate**：真置顶、真勿扰、通知中心、多显示器，仍走 8.4。

#### 8.5.7 设计对照

- `scripts/design-compare.sh <case>`：把 App 截图与 PDF 对应页并排成一张对比图，输出到 `artifacts/design-compare/`。
- 用于设计 review，不做像素 gate；PDF 是 1440×900@2x，App 截图也按 2x 生成。
- 每次大改 UI 后人工看一次，确认「像设计稿」而不只是「和上一版一样」。

#### 8.5.8 截图闭环 checklist

- [ ] App 支持 `--snapshot --case --fixture --out`
- [ ] 12–15 个核心 case + 基线
- [ ] `jingli-snapshot-diff` Swift 工具
- [ ] `scripts/snapshot.sh` + `--update`
- [ ] `report.json` 带 mismatch ratio 和 diff 路径
- [ ] `self-test.sh --fast` 包含核心 snapshot
- [ ] 基线更新走单独 commit
- [ ] CI 跑 smoke 子集；本机跑全量
- [ ] `scripts/design-compare.sh` 对照 PDF

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 范围蔓延 | 精力层变成记录负担，v1 迟迟不能日用 | 冻结 v1 范围；精力层放 v1.1 |
| 计时器 bug | 睡眠 / 时钟跳变 / 重复记账导致统计错误 | Core 单点计时；`credited` 幂等；先写单元测试 |
| 迁移丢失 | 只导任务/项目，旧番茄历史不导；用户误以为历史还在 | 导入向导明确写「只导入当前任务/项目，不导入历史」；旧历史不展示 |
| 沙盒 / 签名 | 本地 socket + CLI 受 entitlement 限制 | 个人使用不做沙盒；Developer ID 签名 |
| 设计还原 | 一边写逻辑一边调像素，效率低 | 先做 design tokens，再做页面 |
| Agent 安全 | Agent 误删 / 误改 | 本地 socket + token；破坏性操作 confirm；审计 + undo |
| 完成弹窗过于置顶 | 挡住全屏演示 / 录屏 / 会议共享，或被误认成系统弹窗 | 默认置顶但支持一键收起；可选 30 秒无操作降级；投屏 / 录屏时自动降级（可设置） |
| 勿扰依赖 Shortcuts | 未创建快捷指令 / 自动化权限被拒 / 系统升级改行为，导致勿扰开关失效 | 启动时检查 `shortcuts list`；失败只提示不阻塞；状态字段 + 启动补关闭，避免勿扰留在开启状态 |
| 勿扰误关其他 Focus | 结束时把用户原本的「工作 / 睡眠」Focus 一起关掉 | 开始前用 `INFocusStatusCenter` 判断；已有 Focus 默认不接管；提供「总是接管」显式选项 |
| Mock 与真实系统偏差 | 自测全绿，真机却失败 | 每个 mock 边界保留一条真实 smoke；macOS 升级重跑手工矩阵；维护 `known-unautomatable.md` |
| 手工 gate 被跳过 | 发版后才发现全局窗口 / 勿扰 / 通知问题 | `release-gate.sh` 检查 P0 手工证据；没有证据不允许打 tag |
| macOS 兼容 | 只支持 macOS 26 限制使用场景 | deployment target 设 macOS 15+；Liquid Glass 可选 |

---

## 10. 决策与默认值（v1 基线）

除技术栈外，以下按「个人使用、先跑起来、后续可改」的原则定默认值；不再阻塞 Phase 0。

| 项目 | 决定 | 说明 |
|---|---|---|
| 技术栈 | **SwiftUI + AppKit** | 2026-10-22 已定 |
| 精力层 | **v1 不含；v1.1 只做今日 check-in** | 不做历史复盘 |
| 统计口径 | **只算今天**；日总番茄按整数；单任务按 `1/n`；不做 7 天 / 30 天 | 2.5 / 3.5 视为设计示意 |
| 跨午夜 | 按**结束时间**归属，只影响今天 | 23:50–00:15 算结束日；跨天清空 |
| 数据保留 | **只保留今天**；跨天删除 `focus_session` | 任务 / 项目保留，已完成任务保留完成状态 |
| HTML 数据 | 只导任务 / 项目 / 今日计划；旧番茄历史不导 | 导入向导明确提示 |
| 产品名 | 显示名「精力管理」，内部代号 `jingli` | bundle id `com.freedom-shen.jingli` |
| 同步 | v1 只本地 + 每日 JSON 备份（保留 14 天）+ 手动导出 | iCloud 放 v1.1 |
| Agent | **CLI + `SKILL.md`；MCP 可选，v1 不做** | 不做内嵌聊天；外部 Agent 通过 CLI 操作 |
| 计时长度 | v1 固定 25 分钟 | v1.1 再开放 15 / 25 / 45 / 50 |
| 休息 | 独立 5 分钟，可跳过，不提供暂停，不计入统计 | 休息结束用通知提醒 |
| 再来一轮 | 复用本轮未完成任务 | 已完成 / 已移出自动排除 |
| 完成后按钮 | 浮窗「废弃本轮」改为「关闭」 | 完成后不再用「废弃」语义 |
| 全局弹窗降级 | 默认不自动降级；设置里可选 30 秒后收起 | 默认满足「最前端」 |
| 多显示器 | 出现在鼠标所在屏幕并居中 | 只出现一次 |
| 勿扰 | 接受两个 Shortcuts；默认保留已有 Focus；休息关闭勿扰 | 首次启动引导创建 |
| 主窗口 | 默认 1440×900，最小 1100×700，记忆位置 | 深色、隐藏标题栏 |
| 通知 | 首次开始计时时请求权限；声音开；尊重系统勿扰 | 拒绝后不反复弹 |
| 语言 | v1 简体中文；英文 v1.1 | 日期 / 时区按系统 |
| 更新 | v1 手动构建安装，不做自动更新 | 个人使用足够 |
| 生命周期 | 关窗留在菜单栏；`⌘Q` 退出；开机自启默认关 | 设置里可开 |
| 并发 | 单写 actor / 单队列；CLI 走 Unix socket，不直写 DB | 避免 UI 与 Agent 冲突 |
| 备份 | 每日 JSON，保留 14 天；手动导出随时可用 | 恢复走导入向导 |
| 错误恢复 | DB 损坏从最近备份恢复；磁盘满只读提示；Shortcut 缺失降级 | 不阻塞核心计时 |
| Git 节奏 | **每个阶段结束 `commit` + `push`** | 不积压本地提交；每 Phase 打 tag |
| 测试基线 | 15 个截图 case + CLI contract + 4 个 spike | 见 8.3 / 8.5 |

---

## 11. 调研来源

- [MCP Transports](https://modelcontextprotocol.io/docs/concepts/transports)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Tauri 2 Plugins](https://v2.tauri.app/plugin/)
- [do-not-disturb-cli（说明 macOS 11+ 无公开 Focus API，改用 Shortcuts）](https://github.com/sindresorhus/do-not-disturb-cli)
- [How to Turn on Mac Focus Mode from the Terminal](https://heyfocus.com/blog/how-to-turn-on-mac-focus-mode-from-the-terminal/)
- 本机环境：Xcode 26.0.1、Swift 6.2、macOS 26.6.2、Rust 1.98、Node 20.19

---

## 12. Git 与项目管理

项目从第一天起就用 Git 管理：代码、设计资产、文档、Skill、CLI 全部进同一个私有仓库。这样一次功能提交可以同时改 App、CLI 和 Skill，不会出现版本对不上。

### 12.1 仓库形态：monorepo

```text
jingli/
├─ App/                    # Xcode 工程与 SwiftUI 应用
│  ├─ Jingli.xcodeproj
│  ├─ Jingli/
│  ├─ JingliTests/         # 单元测试
│  └─ JingliUITests/       # XCUITest
├─ Tests/
│  ├─ Fixtures/            # 迁移 JSON、边界任务、测试库
│  └─ Snapshots/           # 页面基准图
├─ Packages/
│  └─ JingliCore/          # 模型、计时器、存储（App/CLI 共用）
├─ CLI/                    # jingli 命令行
├─ MCP/                    # jingli-mcp（v1.1 再建）
├─ Skill/                  # SKILL.md + scripts/install.sh
├─ Design/                 # PDF、AppIcon、截图、设计 token
├─ docs/                   # PRD、架构、ADR、数据模型
├─ scripts/                # 构建、测试、迁移、备份
├─ .gitignore
├─ .gitattributes
├─ CHANGELOG.md
└─ README.md
```

为什么不分仓：

- App、CLI 共享 `JingliCore`，必须同版本发布。
- Agent 相关的改动经常横跨 Core / CLI / Skill，一个 PR 能完整描述。
- MCP 是可选扩展，v1 不建目录也不影响主线。
- 个人项目，分仓只会增加版本同步成本。

Skill 不直接从仓库路径运行；`scripts/install.sh` 负责把 `Skill/jingli/` 复制到 `~/.agents/skills/jingli/`，仓库仍是唯一源。

### 12.2 初始化

```bash
cd /Volumes/ssd/github/2027-10-22-workflow

git init
git branch -M main
git add .
git commit -m "docs: add jingli mac app plan"

# 私有远端：GitHub / GitLab 均可；公司项目换成对应 GitLab 地址
git remote add origin <private-repo-url>
git push -u origin main
```

远端建议设为 private，并保护 `main`：禁止 force push，合并必须走 PR。

### 12.3 分支模型

采用 trunk-based，不设长期 `develop`：

- `main`：始终可构建、可运行。
- 功能分支：`feat/timer-engine`、`feat/agent-bridge`、`fix/day-plan-reset`、`docs/git-workflow`。
- 分支生命周期尽量短，完成后 **rebase merge** 回 `main`，保留功能分支上的分阶段提交；只有提交历史很乱时才 squash。
- **每个阶段结束都要 `commit` + `push` 当前分支**，不要等整个功能做完才推；功能分支先 push，合并后再 push `main`。
- 版本用 annotated tag：`v0.1.0`（Phase 1）、`v0.2.0`（Phase 2）、`v0.3.0`（Phase 3）、`v1.0.0`。
- 预发布用 `v1.0.0-beta.1`；不单独开 release 分支。

### 12.4 Commit 规范

用 Conventional Commits，提交信息写「为什么」，不是「改了什么」。

| 前缀 | 用途 | 示例 |
|---|---|---|
| `feat` | 新功能 | `feat(timer): support shared rounds with 1/n credit` |
| `fix` | 修复 | `fix(day-plan): keep completed main tasks occupying slots` |
| `refactor` | 重构 | `refactor(core): extract DayPlanService` |
| `test` | 测试 | `test(timer): cover pause, resume, sleep and wake` |
| `docs` | 文档 | `docs(plan): add git workflow` |
| `chore` | 杂项 | `chore(repo): add .gitignore and .gitattributes` |
| `build` | 构建 | `build: add xcodegen project spec` |
| `perf` | 性能 | `perf(ui): reduce timer redraws` |

约定：

- 一个 commit 只做一件事；大改动拆成可回滚的几步。
- commit body 说明背景、取舍、验证方式；关联 `Phase 2` 或 issue 编号。
- 不写 `update`、`fix bug`、`wip` 这类信息量为零的标题。
- 提交前跑 `scripts/check.sh`（格式化 + 测试 + 密钥扫描）。

**分阶段提交（完成一个功能时）：**

一个功能不要憋到最后一次性提交，也不要用 `git add .` 一把梭。按下面的顺序拆成若干 commit：

1. `feat(core): ...`：模型 / 数据层
2. `feat(core): ...`：核心逻辑（计时、分摊、状态机）
3. `feat(ui): ...`：界面 / 交互
4. `feat(agent): ...`：CLI / Skill（如果涉及；MCP 可选）
5. `test(...): ...`：补边界测试
6. `docs(...): ...`：更新文档 / CHANGELOG

规则：

- 每个 commit 都要能构建；至少跑过 `scripts/check.sh`，不要提交半截代码到 `main`。
- 每个 commit 只解决一个子问题，commit body 写清楚这一步做了什么、为什么。
- 测试不要全部留到最后；可以跟逻辑同一个 commit，也可以单独一个 `test:` commit。
- 功能完成 = 代码 + 测试 + 文档 + CHANGELOG 都已提交；PR 描述里列出 commit 顺序。
- 合并用 rebase，保留这些 commit；`squash` 只用于清理临时 WIP。

以「完成弹窗」为例：

```text
feat(timer): add finished state and one-time credit
feat(timer): add global completion panel skeleton
feat(timer): add break and next-round actions
test(timer): cover 1/2/3/4-way split and relaunch
test(ui): add completion panel and break flow
docs(timer): document state machine and test cases
```

**阶段提交与推送（硬规则）：**

每个阶段结束 = **commit + push**，不是只 commit。

- 功能分支每完成一个子阶段（模型 / 逻辑 / UI / 测试 / 文档）就 commit + push 到 origin；开 draft PR 让进度可见。
- `main` 合并后立即 `git push origin main`，保持远端与本地一致。
- 每个 Phase 结束打 tag 并 push tag；tag 打在合并后的 `main` 上。
- 推送失败 / 离线：把待推 commit 记在任务里，恢复网络后立刻补推；不允许连续积压多个阶段。
- 每次 push 后，在 PR / 任务记录里写远程 commit hash（`git rev-parse --short HEAD`）。

| 阶段 | 完成标志 | Git 动作 |
|---|---|---|
| 子阶段 | 一个逻辑切片可构建 | commit + push 功能分支 |
| Phase 0 | 骨架 + 4 个 spike 通过 | merge `main` + push + tag `v0.0.1-phase0`（可选） |
| Phase 1 | 核心闭环可日用 | merge `main` + push + tag `v0.1.0` |
| Phase 2 | 功能对齐 + 迁移 | merge `main` + push + tag `v0.2.0` |
| Phase 3 | Agent CLI 端到端 | merge `main` + push + tag `v0.3.0` |
| Phase 4 | 完整一天 + 跨天重置通过 | merge `main` + push + tag `v1.0.0` |
| v1.1 | 精力层 / MCP 可选 | merge `main` + push + tag `v1.1.0` |

### 12.5 提交什么、忽略什么

**提交：**

- 源码、测试、`Package.resolved`
- 设计 token、设计稿、截图
- `docs/`、`CHANGELOG.md`
- `Skill/`、`scripts/`
- `.xcodeproj`（v1 单人开发先提交；如果后续多 Agent 并行改工程，再切 XcodeGen，提交 `project.yml`，忽略 `.xcodeproj`）

**忽略：**

```gitignore
.DS_Store
build/
DerivedData/
*.xcuserstate
xcuserdata/
.swiftpm/
*.log
*.p12
*.mobileprovision
*.cer
*.key
secrets/
```

应用数据目录 `~/Library/Application Support/Jingli/` 永远不进仓库；测试用 `Fixtures/` 里的假数据。Agent token、数据库备份、导出文件都不提交。

`.gitattributes` 建议：

```gitattributes
* text=auto eol=lf
*.pbxproj text eol=lf
*.png binary
*.jpg binary
*.pdf binary
*.mov binary
```

设计资产超过 5MB 时用 Git LFS；`.pbxproj` 不要用 `merge=union`，冲突时重新生成或手动解决。

### 12.6 文档与版本

- `docs/PRD.md`：产品范围与口径
- `docs/plan.md`：本规划（当前文件可以移进去）
- `docs/architecture.md`：架构与模块边界
- `docs/data-model.md`：表结构与迁移
- `docs/adr/0001-native-swiftui.md`、`0002-agent-unix-socket.md`：关键决策记录
- `CHANGELOG.md`：Keep a Changelog 格式，只写用户可见变化

版本号同步到 Xcode 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`；打 tag 前更新 CHANGELOG。

### 12.7 Issue、里程碑与 PR

- 用 GitHub Projects 或 GitLab Board，列：Backlog / This week / In progress / Review / Done。
- Label：`phase-0`…`phase-4`、`area:ui`、`area:timer`、`area:agent`、`area:data`、`type:feature`、`type:bug`、`type:docs`。
- Milestone：`v0.1 skeleton`、`v0.2 core`、`v0.3 agent`、`v1.0`。
- 即使单人开发也走 PR：diff 可回看，Agent 也能在分支上工作。

PR 模板：

```markdown
## What
一句话说明改了什么。

## Why
对应 Phase / issue，解决什么问题。

## Commit sequence
按顺序列出分阶段提交，例如：
1. feat(timer): add finished state and one-time credit
2. feat(timer): add global completion panel skeleton
3. test(timer): cover 1/2/3/4-way split and relaunch
4. docs(timer): document state machine and test cases

## How tested
- [ ] `scripts/check.sh`
- [ ] 手动路径：…
- [ ] 截图（UI 改动）

## Checklist
- [ ] 测试通过
- [ ] 文档 / CHANGELOG 已更新
- [ ] 无密钥、无个人数据、无本地路径
```

### 12.8 CI

GitHub Actions 或 GitLab CI，macOS runner：

- PR：`scripts/self-test.sh --fast`（build + unit + integration + UI smoke + snapshots + lint）。
- Nightly：`scripts/self-test.sh --full`（全量 UI + 性能 + 假时钟跨天重置模拟）。
- `swift test`（JingliCore / CLI）；`xcodebuild test -only-testing:JingliUITests`（UI）。
- `swiftformat --lint`、`swiftlint`、`shellcheck scripts/*.sh`。
- 缓存 SPM 依赖；上传 `artifacts/`、xcresult、失败截图。
- 测试报告：`scripts/report.sh` 生成 `summary.md` + `report.json`，PR 里自动贴摘要。

Release job 在 tag 时触发：archive → 导出 `.app` → zip / dmg → 可选 notarize → 附到 Release。个人使用可以只在本地打包，CI 先跑测试。

签名证书、`.p12`、描述文件只放 CI secrets 或本机 Keychain，不进仓库。

### 12.9 Agent 协作规则

- Agent 只在自己的 `feat/...` / `fix/...` 分支工作，不直接 push `main`。
- 并行任务用 `git worktree`，一个任务一个工作区，避免互相踩文件。
- 提交前必须跑 `scripts/check.sh`；提交信息用 Conventional Commits。
- **必须分阶段提交**：一个功能拆成多个逻辑 commit，禁止一个 commit 塞完整个功能；每个 commit 都要能构建。
- **每个阶段结束必须 push**：commit 后立即 `git push origin <branch>`；禁止只在本地积压多个阶段。push 后在任务/PR 里写远程 commit hash。
- Agent 可以开 PR，但合并由人确认；PR 描述里列出 commit 顺序、每一步的验证结果和已 push 的 hash。
- 禁止 `git push --force` 到 `main`；禁止提交 token、数据库、备份、真实任务数据。

### 12.10 备份

- 私有远端 + 本地镜像：

```bash
git clone --mirror <private-repo-url> /Volumes/ssd/backups/jingli.git
```

- 每次发版打 tag 并 push：`git push origin --tags`。
- 数据库备份单独存，不进 Git；Git 只管理代码、设计、文档。
- 每月跑一次 `git fsck`，确认镜像完整。

---

## 13. 下一步

可以开始：按 **第 15 节 P0-1 ~ P0-7** 执行，不再需要拍板。

Phase 0 的五件事（不写业务代码）：

1. 第 10 节默认值已定；按该表执行。
2. 一页 PRD：把「只管今天」、跨天规则、迁移边界写死。
3. 数据模型 + 迁移 JSON schema + `Tests/Fixtures/` 样例。
4. SwiftUI 工程骨架 + 设计 token + 空页面导航 + `--snapshot` 模式。
5. 测试骨架：`scripts/self-test.sh` + `scripts/snapshot.sh` + 临时测试库 + 1 个截图基线。

**每一步结束都 `commit` + `push`；不要攒到最后。** Phase 0 每完成一个 spike，也单独 commit + push。

开工前先做 4 个 spike（每个 0.5–1 天），验证最危险的假设：

- [ ] **Shortcuts 勿扰**：创建 `Jingli Focus On/Off`，用 `shortcuts run` 开关勿扰；验证已有 Focus、自动化权限被拒、重命名。
- [ ] **全局 NSPanel**：覆盖全屏应用 / 所有 Space / Stage Manager；第一次点击可点；不抢键盘焦点。
- [ ] **截图模式**：`cacheDisplay` 能稳定抓 SwiftUI 页面 + NSPanel + 菜单栏；连续两次截图无差异。
- [ ] **数据与并发**：SQLite + Unix socket + CLI 同时写（MCP 可选）；任务/项目导入；旧番茄历史不导；今日统计一致。

这 4 个 spike 过了，才算真正「不缺」；没过就先调整方案（例如勿扰降级为手动开关、或调整截图方案）。**SwiftUI 已定，不再改栈。**

现在不缺的是**规划**；缺的是 **P0 的实物和这 4 个 spike 的验证**。第一阶段目标：P0-1 ~ P0-7 全过，然后进 P1。

---

## 14. 决策记录

| 日期 | 决策 | 理由 | 影响 |
|---|---|---|---|
| 2026-10-22 | 采用 **SwiftUI + AppKit** | 核心体验是系统级 ambient UI（菜单栏、浮窗、通知、全局快捷键）；只有 4 个页面，原生工作量可控；后续接 EventKit / SMAppService / Swift Charts 更顺 | 不做 Tauri / WKWebView；工程用 Xcode + SwiftUI；浮窗与完成弹窗直接走 `NSPanel` |
| 2026-10-22 | **默认值锁定；MCP 降为可选** | 先跑起来；CLI + SKILL.md 已足够覆盖 Agent 输入 | v1 不实现 MCP、不含精力层、固定 25 分钟；详见第 10 节 |
| 2026-10-22 | **范围收敛为「只管今天」** | 产品本来就是一天的工具；历史不是需求 | 不做 7 天 / 30 天图表；不迁移旧番茄历史；跨天清空；Phase 4 改为完整一天 + 跨天重置 |

对应 ADR：`docs/adr/0001-native-swiftui.md`（已创建）。

---

## 15. 剩余工作清单（开工 → 闭环）

### 15.1 当前状态

- 文档、决策、图标、Git：完成。
- **P0-5 已完成**：Xcode 工程 + `JingliCore`，build/test 通过，app 可启动。
- **P0-6 已完成**：SQLite schema / migration / rollover / purge + `Tests/Fixtures/`，11 个测试通过。
- **P0-2 代码 spike 已完成**：`level=1000`、`collectionBehavior=321`（可跨 Space / 全屏）、first-mouse override；全屏 / Stage Manager 手工验证待做。
- **P0-3 已完成**：`--snapshot` 抓主窗口 1440×900 + 浮窗 260×360；连续两次截图 0 像素差异；`jingli-snapshot-diff` 可用。
- **P0-7 已完成**：`scripts/self-test.sh --fast/--full` 跑通；基线 `phase0-main.png` / `phase0-panel.png`。
- **P0-4 已完成**：App 内 Unix socket + CLI；`socket=0600`、`ping=pong`、20 个并发 `task add` 最终 `count=20`。
- **P0-1 代码完成**：`FocusController` + `ProcessShortcutRunner` + 设置指南 + 2 条测试；真实 On/Off 需要先创建 `Jingli Focus On/Off` 两个快捷指令。
- 剩余：P0-1 真实快捷指令验证、P0-2 全屏 / Space 手工验证。

### 15.2 开工门槛（P0，2–3 天）

| # | 事项 | 完成标志 |
|---|---|---|
| P0-1 | 🟡 Shortcuts 勿扰 spike（代码完成） | `FocusController` / `focus-spike.sh` / 指南就绪；真实 On/Off 待创建两个快捷指令 |
| P0-2 | 🟡 全局 NSPanel spike（代码完成） | `level=1000`、`collectionBehavior=321`、first-mouse 通过；全屏 / Space / Stage Manager 手工待做 |
| P0-3 | ✅ 截图 spike（2026-10-22） | 主窗口 + 浮窗可抓图；连续两次 0 差异；diff 工具可用 |
| P0-4 | ✅ 数据 / socket / CLI spike（2026-10-22） | socket 0600；20 并发写入后 count=20；`self-test --fast` 已包含 |
| P0-5 | ✅ Xcode 工程 + JingliCore（2026-10-22） | 空页面能跑；build/test 通过；app 可启动 |
| P0-6 | ✅ 数据模型 / 迁移 / fixtures（2026-10-22） | schema、rollover、purge、项目删除保任务；16 tests |
| P0-7 | ✅ snapshot + self-test（2026-10-22） | `self-test --fast/--full` 通过；2 张基线；0 差异 |

P0 完成：merge `main` + push + tag `v0.0.1-phase0`（可选）。

### 15.3 P1 核心闭环（5–7 天）

当前进度：项目 CRUD UI、项目列表 / 详情、新建 / 编辑 / 删除、项目内添加任务已接并实测。重启恢复实测：60 秒计时中强制退出 App，重开后主窗口与菜单栏都恢复为 `00:44`，任务保持暂停 / 继续状态。休息链路已实测；通知代码已接。

- [x] 任务 / 项目 CRUD（任务创建 + 项目列表 / 详情 / 新建 / 编辑 / 删除）
- [x] 开启一天（项目分组 / 勾选 / 4 主线 / 开始，截图验证）
- [ ] 今日页（主线 / 临时 / 完成 / 播放已接；详情未接）
- [x] 计时器（基础链路 + 共享轮次 + `1/n` + 持久化；DND 真实开关待快捷指令）
- [x] 菜单栏倒计时（`24:56 → 24:32` 实测）
- [ ] 浮动番茄钟（计时 / 暂停 / 废弃已接；拖动位置记忆未接）
- [x] 全局完成弹窗（NSPanel + 分摊 + 休息 / 再来一轮 / 关闭；休息实测）
- [ ] 勿扰联动（代码已接；真实 On/Off 待两个快捷指令）
- [ ] 通知 + 声音（代码已接；真实权限 / 横幅待验）
- [x] 重启恢复（60s 计时退出重开 → `00:44`；睡眠唤醒仍待真机）
- [ ] 完整一天验收

P1 完成：merge `main` + push + tag `v0.1.0`。

### 15.4 P2 完整 v1（4–6 天）

- [ ] 项目页 / 未分类
- [ ] 今日统计（KPI + 今日记录，无 7 天图）
- [ ] 设置页（计时固定 25、通知、开机自启、Agent、勿扰）
- [ ] 导入（只导任务 / 项目 / 今日计划）
- [ ] 跨天重置
- [ ] AppIcon 进 Assets
- [ ] 12–15 个截图基线
- [ ] 设置 / 弹窗 / 菜单栏 / 窄屏 / 空状态 / onboarding 设计补齐

P2 完成：merge `main` + push + tag `v0.2.0`。

### 15.5 P3 Agent（4–5 天）

- [ ] Unix socket + JSON-RPC
- [ ] CLI（today / task / day / focus / stats）
- [ ] SKILL.md
- [ ] 审计 / 撤销
- [ ] `⌘K` 命令条
- [ ] CLI contract 测试
- [ ] 端到端：「帮我排今天的主线」

P3 完成：merge `main` + push + tag `v0.3.0`。

### 15.6 P4 交付闭环（2–3 天）

- [ ] 完整一天 dogfood + 跨天重置
- [ ] 手工 gate：全局弹窗 / 勿扰 / 通知 / 多显示器
- [ ] 性能：内存 < 150MB、计时误差 < 1s
- [ ] 可访问性：键盘 / VoiceOver 基本可用
- [ ] 签名 / 公证 / 干净机器启动
- [ ] README / CHANGELOG
- [ ] 备份 / 恢复演练
- [ ] release gate + tag `v1.0.0`

### 15.7 设计缺口

- [ ] 设置页
- [ ] 任务 / 项目编辑弹窗
- [ ] 删除确认弹窗
- [ ] 菜单栏面板
- [ ] 窄屏 1280 布局
- [ ] 空状态 / 错误状态
- [ ] 首次启动 onboarding（通知、勿扰快捷指令、开机自启）
- [ ] 图标的 macOS squircle 透明边角版本（可选）

### 15.8 测试缺口

- [ ] `Tests/Fixtures/` 夹具
- [ ] 单元测试（计时、分摊、跨天）
- [ ] 15 个截图基线
- [ ] 3–5 条 XCUITest 交互 smoke
- [ ] CLI contract 测试
- [ ] `docs/test-plan.md`
- [ ] `docs/manual-test.md`
- [ ] `docs/known-unautomatable.md`
- [ ] `scripts/release-gate.sh`

### 15.9 闭环定义（DoD）

- **功能**：一个完整工作日能从头用到尾，跨天重置正确。
- **工程**：unit + snapshot + CLI 测试通过；每阶段 commit + push。
- **交付**：签名 app 能在干净机器打开，图标正常，备份能恢复。
- **验证**：真实完整一天 + 跨天重置；勿扰 / 全局弹窗 / 通知手工过一遍。

### 15.10 最短路径

- **完整 v1**：2–3 周（每天 2–3 小时）。
- **个人 MVP**：Phase 0 + P1 + 今日统计，1–1.5 周；CLI 可后补。
- **不阻塞**：MCP、精力层、英文、iCloud。

### 15.11 开始条件

- [x] 技术栈：SwiftUI + AppKit
- [x] 默认值：第 10 节
- [x] 图标：`Design/AppIcon/`
- [x] Git：已绑定，每阶段 commit + push
- [ ] P0-1 ~ P0-7

P0-1 ~ P0-7 完成即可进入 P1，不需要再拍板。
