# 勿扰模式 Shortcuts 设置

App 通过两个快捷指令控制「勿扰模式」：

- `Jingli Focus On`
- `Jingli Focus Off`

## 创建步骤

1. 打开 **Shortcuts.app**
2. 新建快捷指令，命名为 `Jingli Focus On`
3. 添加动作 **Set Focus**
4. Focus 选择 **Do Not Disturb / 勿扰模式**
5. 设置为 **Turn On** / **Until Turned Off**
6. 保存
7. 再新建一个 `Jingli Focus Off`，同样的 Focus，设置为 **Turn Off**

## 验证

```bash
shortcuts list | grep "Jingli Focus"
shortcuts run "Jingli Focus On"
shortcuts run "Jingli Focus Off"
```

第一次运行会弹自动化权限；允许即可。如果拒绝，App 会提示「未授权」，不会阻塞番茄钟。

## 注意

- 如果开始番茄前系统已经在「工作 / 睡眠」等其他 Focus，App 默认不接管，也不会在结束时关闭它。
- 如果不想用自动化，可以在设置里关闭「自动勿扰」，改为手动。
