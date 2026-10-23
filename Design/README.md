# 设计稿与视觉资产

- `精力管理-Mac应用设计稿.pdf`：原始 4 页设计稿（开启一天、今日 + 浮窗、完成弹窗、统计）。
- `preview/`：从 PDF 导出的 1440×900 PNG，README 直接引用。
- `AppIcon/`：App 图标源文件、squircle 版本、iconset、icns。

## 重新导出预览图

```bash
swift /tmp/render-pdf.swift "Design/精力管理-Mac应用设计稿.pdf" Design/preview
```

（渲染脚本使用 PDFKit，按页面原始尺寸输出 PNG。）

## 说明

设计稿第 4 页包含「近 7 天番茄钟」柱状图；v1 UI 未实现该图表，统计页只展示今日 KPI + 今日记录，历史通过 CLI / Skill 查询。
