---
name: jingli
description: 管理「精力管理」Mac App 的项目、任务、今日计划、番茄钟与统计。当用户说「新建一个项目」「加个任务」「帮我排今天的主线」「开启番茄钟 / 开始专注」「今天专注了多久」时使用。
---

# 精力管理（jingli）

通过本地 Unix socket 调用 App，不直接改数据库。所有命令输出 JSON。

## 能力总览

| 能力 | 命令 |
|---|---|
| 查看今天 | `jingli today` |
| 项目：列表 / 新建 / 修改 / 删除 | `jingli project list` / `add` / `update` / `delete` |
| 任务：列表 / 新建 / 修改 / 完成 / 恢复 / 删除 | `jingli task list` / `add` / `update` / `complete` / `reopen` / `delete` |
| 今日计划：预演 / 保存 / 开始 / 重置 | `jingli day plan` / `day start` / `day reset` |
| 番茄钟：开始 / 状态 / 暂停 / 继续 / 加任务 / 移任务 / 停止 | `jingli focus …` |
| 休息与下一轮 | `jingli focus break` / `skip-break` / `next` |
| 今日统计 | `jingli stats` |
| 审计 / 撤销 | `jingli events` / `jingli undo` |

**不能做**：改计时长度（固定 25 分钟）、查历史 / 周报、把任务移到另一个项目、改任务的 lane / 日期。这些需要用户在 App 里操作。

## 快速示例：项目 → 任务 → 开启时钟

```bash
jingli project add "工作" --color blue
jingli task add "写周报" --project 工作 --lane main --date today
jingli task list                 # 拿到 task id
jingli day plan <task-id> --dry-run
jingli day plan <task-id>
jingli day start
jingli focus start <task-id>     # 开始 25 分钟；status 可查剩余时间
```

## 前置检查

```bash
command -v jingli || echo "CLI 未安装"
jingli ping
```

未安装时运行仓库里的 `scripts/install.sh`，或直接用 `~/.local/bin/jingli`。App 未运行时 CLI 会尝试 `open -b com.freedom-shen.jingli`；10 秒仍失败则提示用户先打开 App。

## 先读状态

```bash
jingli today          # dayStarted / selection / tasks / projects
jingli project list   # 项目及其 taskCount
jingli task list      # 未完成任务；--all 含已完成
jingli stats          # 今日番茄 / 时长 / 完成任务 / 记录
```

`tasks[].lane` 是 `main`（主线，最多 4 件）或 `temporary`（临时）。

## 项目

```bash
jingli project add "工作" --description "本周重点" --color sage
jingli project update <id> --name "工作（Q4）" --description "季度目标"
jingli project delete <id> --confirm
```

- 颜色可选：`sage` / `amber` / `blue` / `rose` / `violet` / `slate`。
- 删除项目必须 `--confirm`；项目里的任务会保留并移到「未分类」。
- 删除不可撤销。

## 创建与修改任务

```bash
jingli task add "写周报" --project 工作 --lane main --date today
jingli task add "回邮件" --lane temporary
jingli task update <id> --title "写季度周报" --note "重点写复购"
jingli task complete <id>
jingli task reopen <id>
jingli task delete <id> --confirm
```

- `--project` 用项目名称，不是 ID；不存在会报错，先 `project list`。
- `--date today` 只对「今天」有意义；不传则任务先进入未安排。
- `task update` 只能改标题和备注。
- `task delete` 必须 `--confirm`，不可撤销；删除后该任务在今日记录里的分摊也会一起消失（番茄总数不变）。

## 规划今天

1. 从 `task list` 里挑任务，主线最多 4 件。
2. 先 dry-run 校验：

```bash
jingli day plan <id1> <id2> --dry-run
```

3. 用户确认后保存并开始：

```bash
jingli day plan <id1> <id2>
jingli day start
```

4. 回读 `jingli today`，向用户复述今天的主线与临时任务。

重来一天：

```bash
jingli day reset --confirm   # 清空今日计划，任务保留、回到未安排
```

## 开启番茄钟

```bash
jingli focus start <id1> [<id2> ...]   # 开始一轮，支持多任务共享 1/n
jingli focus status                     # active / phase / remainingMs / display / taskIds
jingli focus pause
jingli focus resume
jingli focus add <id>                   # 中途加入当前轮
jingli focus remove <id>                # 中途移出；移空会自动结束
jingli focus stop --confirm             # 废弃本轮，不记账
```

- 固定 25 分钟；开始后 App 自动进入勿扰（需已创建快捷指令）。
- 暂停保持勿扰；完成 / 停止 / 休息会退出由 App 开启的勿扰。
- 一轮结束后 `focus status` 会带 `completion`（任务与 `1/n` 分摊）。

## 休息与再来一轮

```bash
jingli focus break        # 开始 5 分钟休息（需本轮已结束）
jingli focus skip-break   # 跳过休息
jingli focus next         # 复用本轮未完成任务，立即开始下一轮
```

休息不计入统计；`focus next` 只在 `completion` 存在时可用。

## 统计

```bash
jingli stats
```

返回 `pomodoros`（今日番茄数）、`focusSeconds`、`completedTasks`、`records`（每条含 `tasks[].share`）。

## 安全约束

- 破坏性操作必须带 `--confirm`：`task delete`、`project delete`、`day reset`、`focus stop`、`undo`。
- 不要绕过 JSON 输出直接写 SQLite。
- 不要一次排超过 4 件主线；先 dry-run，失败时把错误原文转述给用户。
- 写操作后回读状态，确认结果再向用户汇报。

## 审计与撤销

```bash
jingli events --limit 20
jingli undo --confirm
jingli undo <event-id> --confirm
```

只有带 `undo` 的事件可撤销；删除类操作不可撤销。撤销后回读确认。

## 常见错误

| 输出 | 处理 |
|---|---|
| `破坏性操作需要 --confirm` | 向用户确认后加 `--confirm` |
| `主线任务最多 4 个` | 减少主线，或把其中一件改为临时 |
| `找不到：project X` | 先 `jingli project list`，或用 `project add` 创建 |
| `已有进行中的番茄钟` | 先 `focus stop --confirm`，或用 `focus add` 加入 |
| `本轮尚未结束` | `focus break` / `focus next` 需要先等本轮完成 |
| `无法连接 ...` | App 未运行；提示用户打开「精力管理」 |
