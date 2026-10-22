# 无法完整自动化的边界

以下项目依赖系统 UI、硬件或用户授权，自动化只能覆盖逻辑或替身；发版前按 `manual-test.md` 人工过一遍。

| 项 | 为什么不能自动化 | 现有替代 |
|---|---|---|
| 真实勿扰 Shortcuts | macOS 没有公开 API 设置 Focus；Shortcuts 必须由用户创建并授权 | 单测覆盖所有权 / 顺序；`JINGLI_SHORTCUTS_BIN` fake 覆盖 On/Off 调用；dogfood 验证开始 / 暂停 / 完成 / 退出链路 |
| 真实通知横幅 | 需要系统授权弹窗，且从 `/tmp` 启动的开发包会被 `usernoted` 拒绝 | 已在 `~/Applications` + 全新 bundle id 下人工允许并验证 banner 投递；日常用 `JINGLI_NO_NOTIFICATIONS=1` |
| 系统睡眠 / 唤醒 | 需要真实合盖或 `pmset sleepnow`，会打断当前会话 | `FocusTimer` 单元测试模拟时间跳跃；`endsAt` 逻辑 + 重启恢复已实测 |
| 全屏 / 多 Space / Stage Manager 置顶 | 依赖窗口服务器与用户桌面状态 | 已确认 `level=1000`、`collectionBehavior=321`、first-mouse；视觉矩阵需人工 |
| 完整一天真实使用 | 需要真实 25 分钟 × 多轮与真实任务流 | `scripts/dogfood.sh` 用短计时模拟 3 轮全链路；真实一天仍是 v1.0 发布 gate |
| 通知 / 辅助功能授权 | 系统设置状态无法可靠脚本化 | 设置页给出检查与测试通知入口 |
| 签名 / 公证 / 干净机器 | 需要开发者证书、Apple ID、另一台机器 | `scripts/release-gate.sh` 做本地 Release 构建与签名检查；公证需人工配置 |
