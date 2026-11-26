# 设计稿与视觉资产

- `精力管理-Mac应用设计稿.pdf`：原始 4 页设计稿（开启一天、今日 + 浮窗、完成弹窗、统计）。
- `preview/`：从 PDF 导出的 1440×900 PNG，README 直接引用。
- `AppIcon/`：App 图标源文件、squircle 版本、iconset、icns。
- `ios-design.html`：iOS 版 15 屏设计稿（HTML + CSS，无外部依赖，直接用浏览器打开）。
- `mac-assistant.html`：Mac 端「助手」设计稿（2 屏），沿用 PDF 设计稿的窗口与配色。

## 重新导出预览图

```bash
swift /tmp/render-pdf.swift "Design/精力管理-Mac应用设计稿.pdf" Design/preview
```

（渲染脚本使用 PDFKit，按页面原始尺寸输出 PNG。）

## iOS 设计稿

`ios-design.html` 按五组排列 15 屏：

| 组 | 屏 |
|---|---|
| `#row1` 核心流程 | 开启一天 / 今天 / 专注中 |
| `#row2` 日常操作 | 完成结算 / 项目 / 项目详情 |
| `#row3` 回顾与助手 | 统计 / 设置 / 助手 |
| `#row4` 系统级入口 | 锁屏 Live Activity / 主屏 Widget / 灵动岛三态 |
| `#row5` 语音录入 | 新建任务 / 按住说话 / 解析结果 |

导出单组（`#rowN` 只渲染那一行）与整页长图：

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for n in 1 2 3 4 5; do
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1680,1160 --screenshot="/tmp/ios-row$n.png" \
    "file://$PWD/Design/ios-design.html#row$n"
done
"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1680,5000 --screenshot="/tmp/ios-overview.png" \
  "file://$PWD/Design/ios-design.html"
```

产物在 `preview/`：`ios-01-flow.png` … `ios-05-voice.png`（1680 宽）、`ios-overview.png`（1440 宽整页）。

设计口径与 Mac 端一致：只管理今天、主线最多 4 件、临时任务不挂项目、计时固定 25 分钟、统计不做历史图表；差别只在系统入口（锁屏 / Widget / 灵动岛替代菜单栏与浮窗）。

## Mac 助手设计稿

`mac-assistant.html` 是 PDF 那 4 页之后的第 5、6 屏，同样是 1440×900：

| 屏 | 锚点 | 产物 |
|---|---|---|
| 助手（对话 + 今日上下文 + 模型状态） | `#assistant` | `preview/05-assistant.png` |
| 模型配置（Key 进 Keychain） | `#config` | `preview/06-model-config.png` |

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1440,900 --screenshot=Design/preview/05-assistant.png \
  "file://$PWD/Design/mac-assistant.html"
"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
  --window-size=1440,900 --screenshot=Design/preview/06-model-config.png \
  "file://$PWD/Design/mac-assistant.html#config"
```

`#config` 靠 `:target` 隐藏另一屏——Chrome 的 `--screenshot` 不会自己跳锚点。

设计口径：助手调的是 iOS 那套 `JingliAgent`（同一份 `ToolCatalog`、同一个 `AgentCommandRouter`），所以每条写操作都落成可查看 / 可撤销的卡片；模型配置只多一个「测试连接」，规则（4 件主线、临时不挂项目、预估 1–32）仍然在代码里兜底，不靠提示词。

## 说明

设计稿第 4 页包含「近 7 天番茄钟」柱状图；v1 UI 未实现该图表，统计页只展示今日 KPI + 今日记录，历史通过 CLI / Skill 查询。
