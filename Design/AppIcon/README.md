# App Icon

源文件：`AppIcon.pdf`（3D 番茄计时器，黑底）。

## 产物

- `AppIcon-1024.png`：设计稿原始 1024×1024
- `AppIcon-1024-masked.png`：按内容包围盒自动居中 + macOS squircle 透明边角
- `Jingli.iconset/`：macOS 全尺寸 iconset（16–1024）
- `Jingli.icns`：可直接用于 `.app` 的 `CFBundleIconFile`
- `App/Jingli/Assets.xcassets/AppIcon.appiconset/`：App 实际使用的图标

重新生成：

```bash
python3 scripts/make-icon.py
```

脚本会找出非黑内容（番茄）的亮度加权质心，把视觉重心移到画布中心，再缩放 / 加 824px 圆角底板。源素材本身偏心约 (+91, +41)px，脚本会自动修正（包围盒会被底部反光拉偏，所以用质心而不是包围盒）。

## Xcode 使用

Phase 0 建工程后，把 `AppIcon-1024.png` 放进 `App/Assets.xcassets/AppIcon.appiconset/`，`Contents.json` 选择 macOS 1024×1024；或直接使用 `Jingli.icns`。

## 注意

图标是**黑底圆角透明边角**（macOS squircle），不是纯方形。`AppIcon-1024.png` 保持原始设计稿不动，所有居中 / 圆角处理都在生成阶段完成。
