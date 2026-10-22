---
name: jingli
description: 管理「精力管理」Mac App 的今日任务、番茄钟与统计。当用户说「帮我排今天的主线」「开始一个番茄钟」「今天专注了多久」「把某件事放进今天」时使用。
---

# 精力管理（jingli）

通过本地 Unix socket 调用 App，不直接改数据库。所有命令输出 JSON。

## 前置检查

```bash
command -v jingli || echo "CLI 未安装"
jingli ping
```

如果 `jingli` 不在 PATH，使用仓库构建产物：

```bash
/Volumes/ssd/github/2027-10-22-workflow/Packages/JingliCore/.build/debug/jingli
```

App 未运行时 CLI 会尝试 `open -b com.freedom-shen.jingli`；等待 10 秒仍失败则明确告知用户先打开 App。

## 先读状态

```bash
jingli today
jingli project list
jingli task list
jingli stats
```

`today` 返回：`dayStarted`、`selection`、`tasks`、`projects`。`tasks[].lane` 是 `main` 或 `temporary`。

## 规划今天

1. 从 `task list` 里挑任务，主线最多 4 件。
2. 先 dry-run 校验：

```bash
jingli day plan <id1> <id2> --dry-run
```

3. 用户确认后执行：

```bash
jingli day plan <id1> <id2>
jingli day start
```

4. 回读 `jingli today`，向用户复述今天的主线与临时任务。

## 创建与修改

```bash
jingli task add "写周报" --project 工作 --lane main --date today
jingli task add "回邮件" --lane temporary
jingli task update <id> --title "写季度周报" --note "重点写复购"
jingli task complete <id>
jingli task reopen <id>
```

`--project` 用项目名称；项目不存在会报错，先 `jingli project list`。

## 番茄钟

```bash
jingli focus start <id1> [<id2> ...]
jingli focus status
jingli focus pause
jingli focus resume
jingli focus add <id>
jingli focus remove <id>
jingli focus stop --confirm
```

- 开始后 App 会自动进入勿扰（若已配置快捷指令）；结束 / 停止会退出由 App 开启的勿扰。
- 暂停保持勿扰；`focus stop` 会丢弃本轮，不记账，必须带 `--confirm`。

## 统计

```bash
jingli stats
```

返回今日番茄数、专注秒数、完成任务数、今日记录（每条含任务与 `1/n` 分摊）。

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
| `无法连接 ...` | App 未运行；提示用户打开「精力管理」 |
