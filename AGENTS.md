# AGENTS.md

## 项目

「精力管理」macOS App：SwiftUI + AppKit 原生应用，只管理今天。

- `App/`：App 源码与 XcodeGen 工程（`App/project.yml`）。
- `Packages/JingliCore/`：数据层、计时、统计、备份、Agent server、`jingli` CLI。
- `skill/jingli/SKILL.md`：给外部 Agent 用的 Skill。
- `Tests/Snapshots/`：截图基线。
- `精力管理-Mac应用规划.md`：唯一事实来源的设计与路线文档。

## 硬性规则

- 改完代码必须跑 `scripts/self-test.sh --fast`；提交前跑 `--full`。
- 每个阶段结束 `commit` + `push` 到 `main`；不要只本地提交。
- UI 文案改动后先 `scripts/snapshot.sh --update`，基线图随 commit 一起提交。
- 不提交数据库、备份、真实任务数据、token。
- 不改动用户系统设置：勿扰只走用户创建的 Shortcuts，不碰私有 API、不做 Control Center UI 脚本。
- 删除 / 重置等破坏性操作必须在 CLI / Agent 层要求 `--confirm`。
- 新增可交互 UI 元素必须带 `accessibilityIdentifier`，便于 UI 自动化。

## 常用命令

```bash
cd App && xcodegen generate && cd ..

xcodebuild -project App/Jingli.xcodeproj -scheme Jingli \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/jingli-dd build

cd Packages/JingliCore && swift test

scripts/self-test.sh --fast
scripts/self-test.sh --full
scripts/snapshot.sh compare
scripts/snapshot.sh --update
scripts/agent-spike.sh
scripts/dogfood.sh
```

## 测试钩子

- `JINGLI_SUPPORT_DIR`：独立数据目录。
- `JINGLI_TIMER_SECONDS` / `JINGLI_BREAK_SECONDS`：缩短计时。
- `JINGLI_NO_NOTIFICATIONS=1`：关闭真实通知。
- `JINGLI_NO_BACKUP=1`：关闭每日备份。
- `JINGLI_SHORTCUTS_BIN`：替换 `/usr/bin/shortcuts`。
- `JINGLI_FAKE_NOW_MS`：固定当前时间（截图）。

## 提交信息

`feat|fix|test|docs|chore(scope): summary`，英文，单行。
