# 勿扰模式 Shortcuts 设置

> 当前状态：本机已创建 `Jingli Focus On` / `Jingli Focus Off`，并已用系统
> `~/Library/DoNotDisturb/DB/Assertions.json` 验证 On 建立勿扰 assertion、Off 清除。
> `scripts/focus-spike.sh` 可重复校验；换机器或删除后按下面步骤重建。

App 通过两个快捷指令控制「勿扰模式」：

- `Jingli Focus On`
- `Jingli Focus Off`

## 为什么不能脚本创建

`shortcuts` CLI 只有 `run` / `list` / `view` / `sign`，没有 `create`；
Shortcuts 也没有公开的创建 API。本次是通过 Shortcuts.app UI 自动化创建：
「设定专注模式」动作 → 勿扰模式 → 打开/关闭，然后分别命名。

## 验证

```bash
shortcuts list | grep "Jingli Focus"
scripts/focus-spike.sh
```

`focus-spike.sh` 会：
- On 后检查 assertion 数量 ≥ 1；
- Off 后检查 assertion 数量回到 0；
- 如果开始前已有其他勿扰，自动跳过，避免误关。

## 创建步骤

1. 打开 **Shortcuts.app**
2. 新建快捷指令，命名为 `Jingli Focus On`
3. 添加动作 **Set Focus**
4. Focus 选择 **Do Not Disturb / 勿扰模式**
5. 设置为 **Turn On** / **Until Turned Off**
6. 保存
7. 再新建一个 `Jingli Focus Off`，同样的 Focus，设置为 **Turn Off**

第一次运行会弹自动化权限；允许即可。如果拒绝，App 会提示「未授权」，不会阻塞番茄钟。

## 注意

- 如果开始番茄前系统已经在「工作 / 睡眠」等其他 Focus，App 默认不接管，也不会在结束时关闭它。
- 如果不想用自动化，可以在设置里关闭「自动勿扰」，改为手动。
