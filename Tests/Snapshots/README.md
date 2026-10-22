# Snapshot Baselines

当前只有 Phase 0 的骨架基线：

- `phase0-main.png`：1440×900 主窗口
- `phase0-panel.png`：260×360 浮动 NSPanel

## 更新

```bash
scripts/snapshot.sh --update
```

只在你确认 UI 变更是预期的时候更新；更新后单独提交 baseline。

## 校验

```bash
scripts/snapshot.sh compare
scripts/self-test.sh --fast
```

## 说明

- 截图由 App 的 `--snapshot` 模式用 `cacheDisplay` 生成，不需要屏幕录制权限。
- 基线会随 Phase 1 的真实页面替换；现在的骨架图只用于验证截图链路。
