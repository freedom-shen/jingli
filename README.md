<p align="center">
  <img src="Design/AppIcon/AppIcon-1024-masked.png" width="120" alt="精力管理 App 图标">
</p>

# 精力管理 · Jingli

一个只服务「今天」的 macOS 番茄钟。

每天从项目里挑最多 4 件主线任务，再带上几件临时任务，一起进入一轮 25 分钟共享番茄钟；结束后按 `1/n` 自动分摊。菜单栏倒计时、置顶浮窗、全局完成弹窗和系统通知，让你在写代码、开会、切应用时都不用回到主窗口。

界面刻意不堆历史：打开就是今天，跨天自动清空今日视图，未完成任务回到未安排。但**数据不会丢**——`jingli` CLI 和 Agent Skill 可以按天回顾「哪天完成了哪些任务、花了多少时间」。

原生 **SwiftUI + AppKit**，本地 **SQLite**，Agent 通过 **Unix socket + CLI + Skill** 接入，没有云同步，也没有账号。

## 设计稿

完整 4 页设计稿：[精力管理-Mac应用设计稿.pdf](Design/精力管理-Mac应用设计稿.pdf)

| 开启一天 | 今日任务 + 浮窗 |
| --- | --- |
| ![开启一天](Design/preview/01-day-start.png) | ![今日任务](Design/preview/02-today.png) |
| **完成弹窗** | **统计设计稿** |
| ![完成弹窗](Design/preview/03-completion.png) | ![统计](Design/preview/04-stats.png) |

> 设计稿第 4 页包含「近 7 天番茄钟」柱状图；v1 的 UI 没有做这张图，统计页只显示今日 KPI + 今日记录。历史回顾通过 CLI / Skill 的 `stats --days` 提供。

## 为什么是「只管今天」

- **减少决策成本**：每天只选 4 件主线，避免面对一个无限长的 backlog。
- **共享番茄钟**：多个任务同时计时，结束时按参与任务均分 `1/n`，不重复记账。
- **界面不背历史包袱**：主界面只展示今天；需要复盘时用 Agent 查按天历史，而不是把图表塞进每天的工作界面。
- **本地优先**：数据只在本机 SQLite，备份是可直接阅读的 JSON。

## 功能

- **开启一天**：按项目分组勾选任务，主线最多 4 件，支持临时任务。
- **今日**：主线 / 临时分区；播放、暂停、完成、任务详情（标题 / 备注 / 今日番茄）。
- **共享番茄钟**：25 分钟固定，多任务 `1/n` 分摊；暂停、继续、废弃、休息 5 分钟、再来一轮。
- **全局反馈**：菜单栏倒计时、置顶浮窗（跨 Space、位置记忆）、全局完成弹窗、系统通知（含「开始休息 / 再来一轮 / 回到清单」操作）。
- **勿扰联动**：开始专注运行 `Jingli Focus On`；完成 / 废弃 / 休息 / 退出运行 `Jingli Focus Off`；已有 Focus 时不接管。
- **项目**：项目列表、详情、颜色、新建 / 编辑 / 删除；删除项目时任务保留并移到未分类。
- **统计与历史**：今日 KPI + 今日记录；`jingli stats --days N` / `--date` 按天回顾番茄、专注时长、完成任务与每轮记录。
- **设置**：勿扰开关、快捷指令检查、测试通知、每日 JSON 备份 / 导入、开机自启。
- **Agent**：Unix socket JSON-RPC + `jingli` CLI + `skill/jingli/SKILL.md`；支持项目 / 任务 / 排期 / 计时 / 统计 / 审计 / 撤销。
- **跨天**：UI 回到「开启一天」；未完成任务回未安排；番茄、日计划与任务完成事件保留供历史查询。

## 环境

- macOS 15+
- Xcode 26（Swift 6）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 图标生成可选：Python 3 + Pillow

## 构建、打包与安装

开发调试：

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/Jingli.xcodeproj -scheme Jingli \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/jingli-dd build
open /tmp/jingli-dd/Build/Products/Debug/Jingli.app
```

打包并安装到 `/Applications`：

```bash
scripts/package.sh            # Release 构建 + zip + 替换 /Applications/Jingli.app
scripts/package.sh --run      # 安装后启动
scripts/package.sh --no-install   # 只构建 + zip
scripts/package.sh --no-zip       # 只构建 + 安装
scripts/package.sh --install-dir ~/Applications
SIGN_IDENTITY=<证书 SHA-1 或名称> scripts/package.sh
NOTARY_PROFILE=<keychain profile> scripts/package.sh   # 可选公证
```

产物：

- `/Applications/Jingli.app`
- `artifacts/release/Jingli-<version>.zip`

独立数据目录运行（不污染正式数据）：

```bash
JINGLI_SUPPORT_DIR=/tmp/jingli-dev \
  /tmp/jingli-dd/Build/Products/Debug/Jingli.app/Contents/MacOS/Jingli
```

## CLI 与 Skill

```bash
scripts/install.sh   # 安装 jingli 到 ~/.local/bin，并链接 skill 到 ~/.agents/skills/jingli
```

常用命令：

```bash
jingli today
jingli project add "工作" --color blue
jingli task add "写周报" --project 工作 --lane main --date today
jingli day plan <id...> --dry-run
jingli day plan <id...>
jingli day start
jingli focus start <id...>
jingli stats
jingli stats --days 7
jingli stats --date 2026-10-22
jingli events
jingli undo --confirm
```

完整命令与安全约束见 [`skill/jingli/SKILL.md`](skill/jingli/SKILL.md)。

## 统计与历史

```bash
jingli stats --days 7                     # 最近 7 天，含今天，按日期倒序
jingli stats --date 2026-10-22            # 指定一天
jingli stats --date 2026-10-22 --days 3   # 截止该日期的 3 天
```

每天返回：

- `pomodoros`：当天完成的番茄数
- `focusSeconds`：当天专注秒数
- `completedTasks[]`：当天完成的任务（标题 / 完成时间）
- `records[]`：当天每一轮番茄，包含参与任务与 `1/n` 分摊

历史从 **v0.6.0** 开始保留；升级前按旧策略清掉的记录无法恢复。

## 数据与备份

- 数据目录：`~/Library/Application Support/Jingli/`
  - `jingli.sqlite`：SQLite（WAL）
  - `Backups/jingli-YYYY-MM-DD.json`：每日首次启动自动备份，保留 14 天
  - `agent.sock`：本地 Agent socket（`0600`）
- `JINGLI_SUPPORT_DIR` 可覆盖数据目录，测试 / 多环境隔离用。
- 备份 / 导入只覆盖项目、任务与今日计划；历史番茄记录在 SQLite 中。

## 勿扰快捷指令

见 [`docs/focus-shortcuts.md`](docs/focus-shortcuts.md)。

1. `Jingli Focus On`：Set Focus → 勿扰模式 → 打开。
2. `Jingli Focus Off`：Set Focus → 勿扰模式 → 关闭。

未创建时计时不受影响，设置页会显示「未配置」。

## 测试

```bash
scripts/self-test.sh --fast    # unit + app tests + 4 场景截图 + agent spike
scripts/self-test.sh --full    # 额外跑截图 determinism + 模拟一天 dogfood
scripts/snapshot.sh compare
scripts/snapshot.sh --determinism
scripts/dogfood.sh             # 3 轮短计时、共享分摊、休息、再来一轮、统计、重置、备份、跨天、历史
scripts/agent-spike.sh
```

当前：**53 个 Core 测试**、App 测试、4 个状态 / 6 张截图基线（`day-start` / `today-running` / `stats` / `completion`）。

## 测试钩子

| 环境变量 | 作用 |
|---|---|
| `JINGLI_SUPPORT_DIR` | 覆盖数据目录 |
| `JINGLI_TIMER_SECONDS` | 缩短专注时长（测试） |
| `JINGLI_BREAK_SECONDS` | 缩短休息时长（测试） |
| `JINGLI_NO_NOTIFICATIONS=1` | 关闭真实通知 |
| `JINGLI_NO_BACKUP=1` | 关闭每日备份 |
| `JINGLI_SHORTCUTS_BIN` | 替换 `/usr/bin/shortcuts`（勿扰测试） |
| `JINGLI_FAKE_NOW_MS` | 固定当前时间（截图） |

## 目录

```text
App/                   SwiftUI App（XcodeGen 工程）
Packages/JingliCore/   数据层、计时、统计、历史、备份、Agent server、CLI
skill/jingli/          Agent Skill
scripts/               构建、自测、截图、打包、安装、图标
Tests/Snapshots/       截图基线
Design/                设计稿、预览图、App 图标
docs/                  设计说明、快捷键、测试与验收文档
```

## 已知限制

- UI 只展示今天，不做 7 天 / 30 天图表；历史通过 CLI / Skill 查询。
- 计时 / 休息长度固定 25 / 5 分钟。
- 勿扰依赖两个 Shortcuts；本机已创建并验证，换机器需按文档重建。
- 通知需要用户在系统设置中允许；从 `/tmp` 直接运行开发包时 `usernoted` 可能拒绝校验，安装到 `~/Applications` 或 `/Applications` 后再试。
- 任务删除会同时移除它的完成事件与番茄分摊。
- 未做签名 / 公证 / 自动更新。
