# App Icon

源文件：`AppIcon.pdf`（3D 番茄计时器，黑底）。

## 产物

- `AppIcon-1024.png`：1024×1024，给 Xcode `Assets.xcassets/AppIcon.appiconset` 用
- `Jingli.iconset/`：macOS 全尺寸 iconset（16–1024）
- `Jingli.icns`：可直接用于 `.app` 的 `CFBundleIconFile`

## Xcode 使用

Phase 0 建工程后，把 `AppIcon-1024.png` 放进 `App/Assets.xcassets/AppIcon.appiconset/`，`Contents.json` 选择 macOS 1024×1024；或直接使用 `Jingli.icns`。

## 注意

当前图标是**黑底方形**。如果 Finder / Dock 需要 macOS squircle 透明边角，Phase 0 再生成 masked 版本；不要在设计稿未确认前改掉黑底。
