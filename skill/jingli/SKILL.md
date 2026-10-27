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
| 休息 | `jingli focus break` / `skip-break` |
| 今日统计 | `jingli stats` |
| 历史回顾 | `jingli stats --days N` / `jingli stats --date YYYY-MM-DD` |
| 审计 / 撤销 | `jingli events` / `jingli undo` |

**不能做**：改计时长度（固定 25 分钟）、做周 / 月图表、把任务移到另一个项目、改任务的 lane / 日期。UI 仍然只展示今天；历史通过 CLI / Skill 按天查询。

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

`tasks[].lane` 是 `main`（主线，最多 4 件）或 `temporary`（临时）。每条任务还会带：
- `estimate`：预计要花几个番茄；可能没有这个字段（没估）。
- `note`：纯文本备注，可能为空；卡片上只显示第一行。

App 卡片上显示的是「今天已用 / 预计」，超出预计会标红；预估只影响展示，不限制你多干。

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
jingli task add "回邮件" --lane temporary            # 临时任务：默认直接进今天
jingli task add "先记下" --lane temporary --undated   # 只记录，不排今天
jingli task add "临时插单" --lane temporary --date today
jingli task add "写周报" --project 工作              # 项目主线：先进项目，不自动进今天
jingli task add "写周报" --project 工作 --estimate 3  # 预计 3 个番茄
jingli task update <id> --title "写季度周报" --note "重点写复购"
jingli task update <id> --estimate 2                  # 改预计番茄
jingli task update <id> --clear-estimate              # 取消预估
jingli task complete <id>
jingli task reopen <id>
jingli task delete <id> --confirm
```

- **临时任务**：不限量，随时可加；加完立刻出现在「今日任务 · 临时任务」，不占 4 件主线名额。不传 `--date` 时默认排到今天；只想记下来不排期，就加 `--undated`。**不要在临时任务上挂项目**：项目里的任务默认是主线，挂成临时会让人以为是主线任务。
- **主线任务**：属于项目，只能在项目里创建。要进今天，走「开启一天」或 `day plan` + `day start`；今天已经开始后不能再加主线（会报 `今天已经开始…`），此时只能加不挂项目的临时任务，或把主线留在项目里等明天。
- `--project` 用项目名称，不是 ID；不存在会报错，先 `project list`。
- `--date today` 只对「今天」有意义。
- `--estimate N` 是预计要花几个番茄（1–32）；不填就是没估，任务卡上只显示已用。**不要替用户猜预估**，用户没说就留空；预估只影响展示和当天总量提示，不占主线名额、不限制进度。
- `--note` 是纯文本备注，不渲染任何格式（URL 就当普通文字写），最长 1000 字符；卡片上只显示第一行。适合写复现步骤、验收标准、参考链接。
- `task update` 可改标题、备注和预计番茄（`--clear-estimate` 清空预估）。
- `task delete` 必须 `--confirm`，不可撤销；删除后该任务在今日记录里的分摊也会一起消失（番茄总数不变）。

写一段备注（提示：用 `$'...'` 保留换行）：

```bash
jingli task update <id> --note $'客户反馈地图 region 更新后显示错位。\n\n复现：打开面板 → 右上角搜索 → 地图页，更新区域后截图。\n参考：https://example.com/issue/123'
```

## 预估怎么填

从对话里带出预估，不要多问一句：

- 用户说番茄数（「两个番茄」「估 3 个」）→ `--estimate N`。
- 用户只说时长（「大概一小时」）→ 按 25 分钟一个折算，**向上取整**（1 小时 ≈ 3 个）。
- 用户没说 → 不填；不要替用户猜，也不用追问。
- 用户改口 → `task update <id> --estimate N`，或者 `--clear-estimate`。
- 预估只影响卡片展示和当天总量提示，不占主线名额、不限制进度，不要拿它当排期约束。

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

## 休息

```bash
jingli focus break        # 开始休息（需本轮已结束）：平时 5 分钟，连续 4 个钟后 25 分钟长休
jingli focus skip-break   # 跳过休息
```

按番茄钟规则，本轮结束先休息，不提供「直接下一轮」；休息结束后再 `focus start`。
连续完成 4 个番茄钟（中途没有废弃）后触发长休：App 提示「连续 4 个钟了，休息一下」，下一次休息为 25 分钟。完成一轮 +1；废弃一轮清零；直接开新一轮、跳过休息或跨天也会结束长休待触发状态。
休息不计入统计。`focus status` 额外返回 `consecutiveCompletions`、`longBreakPending`、`breakMinutes`。

## 统计与历史

```bash
jingli stats                              # 今天
jingli stats --days 7                     # 最近 7 天，含今天，按日期倒序
jingli stats --date 2026-10-22            # 指定某一天
jingli stats --date 2026-10-22 --days 3   # 截止该日期的 3 天
```

返回结构：

- 单日（`stats`）：`pomodoros`、`focusSeconds`、`completedTasks`（数字）、`records`
- 历史（`--days` / `--date`）：`days[]`，每天包含
  - `date`
  - `pomodoros`：当天完成的番茄数
  - `focusSeconds`：当天专注秒数
  - `completedTasks[]`：当天完成的任务（`id` / `title` / `completedAt`）
  - `records[]`：当天每轮番茄（`startedAt`、`durationSec`、`tasks[].share`）

注意：

- 历史从 v0.6.0 开始保留；升级前的旧番茄记录已经不存在，无法补回。
- 任务被删除后，它的完成事件和番茄分摊也会一起消失。
- UI 统计页仍然只显示今天；历史只在 CLI / Skill 输出。

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
| `今天已经开始，主线任务只能在项目里维护` | 在项目里建一条不排日期的主线（留到明天）；今天要加就用**不挂项目**的临时任务，不要把项目任务改成临时 |
| `找不到：project X` | 先 `jingli project list`，或用 `project add` 创建 |
| `已有进行中的番茄钟` | 先 `focus stop --confirm`，或用 `focus add` 加入 |
| `本轮尚未结束` | `focus break` 需要先等本轮完成 |
| `无法连接 ...` | App 未运行；提示用户打开「精力管理」 |
