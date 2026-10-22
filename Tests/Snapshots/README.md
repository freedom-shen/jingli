# Snapshot Baselines

状态驱动的视觉回归基线（1440×900，深色主题）：

| 场景 | 文件 | 说明 |
|---|---|---|
| `day-start` | `day-start-main.png` / `day-start-panel.png` | 空状态开启一天 + 空闲浮窗 |
| `today-running` | `today-running-main.png` / `today-running-panel.png` | 两件任务、单任务计时 `12:41` |
| `stats` | `stats-main.png` | 今日 KPI + 一条共享番茄记录 |
| `completion` | `completion-main.png` | 完成弹窗 `+0.5` 分摊 |

## 更新

```bash
scripts/snapshot.sh --update
```

只在你确认 UI 变更是预期的时候更新；更新后单独提交 baseline。

## 校验

```bash
scripts/snapshot.sh compare
scripts/snapshot.sh --determinism
scripts/self-test.sh --fast
```

## 说明

- 截图由 App 的 `--snapshot --snapshot-fixture <scene>` 模式用 `cacheDisplay` 生成，不需要屏幕录制权限。
- 每个场景使用独立的临时 `JINGLI_SUPPORT_DIR`，夹具数据在截图进程内创建。
- 基线只用于本机 macOS 26 / 深色外观；更换字体或系统版本后需要重新生成。
