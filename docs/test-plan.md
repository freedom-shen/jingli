# 测试计划

## 范围

「精力管理」macOS App：数据层、计时 / 统计口径、Agent 接口、UI 状态与视觉回归。

不在自动化范围：真实系统睡眠唤醒、真实勿扰快捷指令、真实通知横幅、跨 App 最前端弹窗、多显示器 / Stage Manager、完整一天真实使用。见 `known-unautomatable.md`。

## 分层

| 层 | 命令 | 覆盖 |
|---|---|---|
| 单元 | `cd Packages/JingliCore && swift test` | 计时、分摊、跨天、统计、备份、Agent 路由、勿扰协调 |
| App 测试 | `xcodebuild … test` | App 层 smoke |
| 截图回归 | `scripts/snapshot.sh compare` / `--determinism` | `day-start` / `today-running` / `stats` / `completion` |
| Agent 契约 | `scripts/agent-spike.sh` | socket 权限、并发写、plan / start / focus / undo、confirm 拒绝 |
| 模拟一天 | `scripts/dogfood.sh` | 3 轮短计时、共享分摊、暂停 / 继续、加 / 移任务、每轮后休息、统计、重置、备份、跨天 |
| 总入口 | `scripts/self-test.sh --fast` / `--full` | 以上全部；`--full` 含 determinism + dogfood |

## 环境

- macOS 15+，Xcode 26，XcodeGen。
- `self-test` 使用独立临时 `JINGLI_SUPPORT_DIR`，不影响真实数据。
- 截图基线只对当前机器 / 系统版本 / 深色外观有效，换环境后 `scripts/snapshot.sh --update`。

## 退出标准

- `self-test --fast` < 3 分钟，`--full` < 15 分钟，全部通过。
- 截图 4 场景 0 像素差异；determinism 连续两次 0 差异。
- agent spike + dogfood 全绿。
- 手工 gate（`manual-test.md`）在发版前至少跑一遍。

## 失败处理

- 先重跑一次确认不是 flaky；flaky case 记录并隔离，不静默重试。
- 截图失败保留 `artifacts/snapshot/*.diff.png` 与 `current/` 原图。
- App 崩溃保留 `/tmp/jingli-*` 日志与 `~/Library/Logs/DiagnosticReports/` 报告。
