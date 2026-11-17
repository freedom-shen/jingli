# 设计稿与视觉资产

- `精力管理-Mac应用设计稿.pdf`：原始 4 页设计稿（开启一天、今日 + 浮窗、完成弹窗、统计）。
- `preview/`：从 PDF 导出的 1440×900 PNG，README 直接引用。
- `AppIcon/`：App 图标源文件、squircle 版本、iconset、icns。
- `ios-design.html`：iOS 版 12 屏设计稿（HTML + CSS，无外部依赖，直接用浏览器打开）。

## 重新导出预览图

```bash
swift /tmp/render-pdf.swift "Design/精力管理-Mac应用设计稿.pdf" Design/preview
```

（渲染脚本使用 PDFKit，按页面原始尺寸输出 PNG。）

## iOS 设计稿

`ios-design.html` 按四组排列 12 屏：

| 组 | 屏 |
|---|---|
| `#row1` 核心流程 | 开启一天 / 今天 / 专注中 |
| `#row2` 日常操作 | 完成结算 / 项目 / 项目详情 |
| `#row3` 回顾与助手 | 统计 / 设置 / 助手 |
| `#row4` 系统级入口 | 锁屏 Live Activity / 主屏 Widget / 灵动岛三态 |

导出单组（`#rowN` 只渲染那一行）与整页长图：

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for n in 1 2 3 4; do
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1680,1160 --screenshot="/tmp/ios-row$n.png" \
    "file://$PWD/Design/ios-design.html#row$n"
done
"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1680,5000 --screenshot="/tmp/ios-overview.png" \
  "file://$PWD/Design/ios-design.html"
```

产物在 `preview/`：`ios-01-flow.png` … `ios-04-system.png`（1680 宽）、`ios-overview.png`（1440 宽整页）。

设计口径与 Mac 端一致：只管理今天、主线最多 4 件、临时任务不挂项目、计时固定 25 分钟、统计不做历史图表；差别只在系统入口（锁屏 / Widget / 灵动岛替代菜单栏与浮窗）。

## 说明

设计稿第 4 页包含「近 7 天番茄钟」柱状图；v1 UI 未实现该图表，统计页只展示今日 KPI + 今日记录，历史通过 CLI / Skill 查询。
