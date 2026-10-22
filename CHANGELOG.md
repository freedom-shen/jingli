# Changelog

## v0.4.0 — 2026-10-22

发布候选：功能主体完成，自动化闭环通过，等待真实一天人工验收。

- 版本号 `0.4.0`；Release 构建通过，Developer ID 签名 + zip 打包脚本可用。
- `scripts/release-gate.sh`：full self-test + Release 构建 + bundle / 签名检查。
- `scripts/release-build.sh`：可选 Developer ID 签名、zip、notarytool 公证。
- `docs/test-plan.md` / `docs/manual-test.md` / `docs/known-unautomatable.md`。

## v0.3.0 — 2026-10-22

功能主体完成，进入人工验收阶段。

### 新增

- 今日统计页：番茄数、专注时长、完成任务数、今日记录（`1/n` 分摊）。
- 设置页：勿扰开关、快捷指令检查、测试通知、备份 / 导入、开机自启、版本信息。
- JSON 备份：每日首次启动自动备份，保留 14 天；支持手动备份与导入（项目 / 任务 / 今日计划）。
- 跨天自动清场：未完成任务回未安排，旧 session / day_plan 删除。
- 任务详情 sheet：改标题 / 备注、完成 / 恢复、查看今日番茄。
- 浮窗位置记忆；屏幕外坐标回退默认位置。
- 全局完成弹窗、休息 / 再来一轮 / 回到清单。
- Agent API：today / task / project / day / focus / stats / events / undo。
- `jingli` CLI 全命令 + `skill/jingli/SKILL.md` + `scripts/install.sh`。
- ⌘K 快速命令条：`开始 <任务>` / `新任务 <标题>` / `统计`。
- 审计与撤销：写操作写 `agent_event`，支持撤销创建 / 修改 / 完成 / 排期。
- App 图标：macOS squircle 圆角透明边角，生成全套 iconset / icns。

### 测试

- 新增 `scripts/dogfood.sh`：模拟一天 3 轮短计时，覆盖共享分摊、暂停 / 继续、加 / 移任务、休息、再来一轮、统计、重置、备份、跨天。
- `self-test --full` 现在包含截图 determinism 和模拟一天。
- 冷启动空闲内存约 102 MB，计时中约 102 MB / 1.3% CPU。

### 改进

- 通知新增 `FOCUS_COMPLETE` 分类与三个操作：开始休息 5 分钟 / 再来一轮 / 回到清单；点击通知默认打开 App 并关闭完成弹窗。
- 菜单栏面板新增「快速添加任务」。

- 勿扰所有权：开始前已有 Focus 时不接管；暂停保持；完成 / 废弃 / 休息 / 退出释放；活跃轮次重启后补开。
- 通知请求与投递链路验证；新增 `JINGLI_SHORTCUTS_BIN` 测试钩子。
- 截图测试升级为状态驱动：`day-start`、`today-running`、`stats`、`completion` 四场景 / 六张基线，连续截图 0 像素差异。
- 快照窗口固定 key 状态，避免前台 App 影响禁用按钮渲染。
- 自测扩展：47 个 Core 测试、App 测试、扩展 agent spike（plan / start / focus / pause / resume / stop / undo）。

### 已知限制

- 真实勿扰快捷指令尚未创建，需按 `docs/focus-shortcuts.md` 手动建两个 Shortcuts。
- 通知授权需用户在系统设置允许；开发包从 `/tmp` 直接运行会被 `usernoted` 拒绝校验，安装到 `~/Applications` 或 `/Applications` 后再授权。
- 睡眠唤醒、完整一天 dogfood、签名 / 公证未完成。
- 计时 / 休息长度固定 25 / 5 分钟；不保留历史、不做周 / 月图表。
