# 精力管理 · Jingli

一款只管理「今天」的 macOS 番茄钟。选最多 4 件主线任务，共同进入一轮 25 分钟专注；结束自动结算 `1/n`，并能通过 CLI / Skill 让 Agent 帮你排今天。

原生 SwiftUI + AppKit，数据只存本地 SQLite。

## 功能

- **开启一天**：按项目分组勾选任务，主线最多 4 件，支持临时任务。
- **今日**：主线 / 临时分区，卡片播放、完成、任务详情（改标题 / 备注 / 查看今日番茄）。
- **番茄钟**：25 分钟固定，多任务共享 `1/n`；暂停、继续、废弃、再来一轮、休息 5 分钟。
- **全局反馈**：菜单栏倒计时、置顶浮窗（跨 Space、位置记忆）、全局完成弹窗、系统通知。
- **勿扰联动**：开始专注运行 `Jingli Focus On`，完成 / 废弃 / 休息 / 退出运行 `Jingli Focus Off`；已有 Focus 时不接管。
- **统计**：今日番茄、专注时长、完成任务、今日专注记录。
- **设置**：勿扰开关、快捷指令检查、测试通知、每日 JSON 备份 / 导入、开机自启。
- **Agent**：Unix socket JSON-RPC + `jingli` CLI + `skill/jingli/SKILL.md`；支持 plan / start / focus / stats / 审计 / 撤销。
- **跨天**：未完成任务回未安排，旧番茄记录和旧计划清空，已完成任务保留。

## 环境

- macOS 15+
- Xcode 26（Swift 6）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 图标生成可选：Python 3 + Pillow

## 构建与运行

```bash
cd App && xcodegen generate && cd ..
xcodebuild -project App/Jingli.xcodeproj -scheme Jingli \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/jingli-dd build
open /tmp/jingli-dd/Build/Products/Debug/Jingli.app
```

独立数据目录运行（不污染正式数据）：

```bash
JINGLI_SUPPORT_DIR=/tmp/jingli-dev \
  /tmp/jingli-dd/Build/Products/Debug/Jingli.app/Contents/MacOS/Jingli
```

## 测试

```bash
scripts/self-test.sh --fast    # unit + app tests + 4 场景截图 + agent spike
scripts/self-test.sh --full    # 额外跑截图 determinism + 模拟一天 dogfood
scripts/snapshot.sh compare
scripts/snapshot.sh --determinism
scripts/dogfood.sh             # 3 轮短计时、共享分摊、休息、再来一轮、统计、重置、备份、跨天
scripts/agent-spike.sh
```

核心测试：

```bash
cd Packages/JingliCore && swift test
```

当前：47 个 Core 测试、App 测试、6 张截图基线（`day-start` / `today-running` / `stats` / `completion`）。

## CLI 与 Skill

```bash
scripts/install.sh   # 安装 jingli 到 ~/.local/bin，并链接 skill 到 ~/.agents/skills/jingli
```

常用命令：

```bash
jingli today
jingli task add "写周报" --project 工作 --lane main --date today
jingli day plan <id...> --dry-run
jingli day plan <id...>
jingli day start
jingli focus start <id...>
jingli stats
jingli events
jingli undo --confirm
```

完整说明见 `skill/jingli/SKILL.md`。

## 数据与备份

- 数据目录：`~/Library/Application Support/Jingli/`
  - `jingli.sqlite`：SQLite（WAL）
  - `Backups/jingli-YYYY-MM-DD.json`：每日首次启动自动备份，保留 14 天
  - `agent.sock`：本地 Agent socket（`0600`）
- `JINGLI_SUPPORT_DIR` 可覆盖数据目录，测试 / 多环境隔离用。

## 勿扰快捷指令

见 `docs/focus-shortcuts.md`。需要手动创建：

1. `Jingli Focus On`：Set Focus → 勿扰模式 → 打开。
2. `Jingli Focus Off`：Set Focus → 勿扰模式 → 关闭。

未创建时计时不受影响，设置页会显示「未配置」。

## 测试钩子

| 环境变量 | 作用 |
|---|---|
| `JINGLI_SUPPORT_DIR` | 覆盖数据目录 |
| `JINGLI_TIMER_SECONDS` | 缩短专注时长（测试） |
| `JINGLI_BREAK_SECONDS` | 缩短休息时长（测试） |
| `JINGLI_NO_NOTIFICATIONS=1` | 关闭真实通知 |
| `JINGLI_NO_BACKUP=1` | 关闭每日备份 |
| `JINGLI_SHORTCUTS_BIN` | 替换 `/usr/bin/shortcuts`（勿扰测试） |

## 目录

```text
App/                   SwiftUI App（XcodeGen 工程）
Packages/JingliCore/   数据层、计时、统计、备份、Agent server、CLI
skill/jingli/          Agent Skill
scripts/               构建、自测、截图、安装、图标
Tests/Snapshots/       截图基线
Design/                设计稿与图标
docs/                  架构与操作说明
```

## 已知限制

- 只管理今天，不保留历史，不提供 7 天 / 30 天图表。
- 计时 / 休息长度固定 25 / 5 分钟。
- 勿扰依赖两个 Shortcuts；本机已创建并验证，换机器需按 `docs/focus-shortcuts.md` 重建。
- 通知需要用户在系统设置中允许；从 `/tmp` 直接运行开发包时 `usernoted` 可能拒绝校验，安装到 `~/Applications` 或 `/Applications` 后再试。
- 未做签名 / 公证 / 自动更新。
