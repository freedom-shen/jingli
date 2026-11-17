# iOS 版现状与验证记录

> 截至 2026-11-17。这份文档回答三件事：**做完了什么、怎么跑起来、哪些是验证过的**。

## 一、这个 iOS App 是什么

Mac 版「精力管理」的手机端。它不是另做一个产品，而是**同一个数据模型的第二个入口**：

- 只管理今天：开启一天 → 最多 4 件主线 + 若干临时任务 → 共享 25 分钟番茄钟 → 按 1/n 分摊
- 数据通过 **iCloud 私有库**在设备间同步，合并规则与 Mac 端完全相同（字段级 LWW + tombstone）
- 助手用同一套 `AgentCommandRouter`（CLI / Agent 协议 / iOS App 三处共用），模型只负责把话变成方法调用

## 二、目录

| 路径 | 内容 |
|---|---|
| `Packages/JingliCore/` | 数据层、同步合并规则、Agent 命令路由、CLI |
| `Packages/JingliCore/Sources/JingliSync/` | 传输抽象、SyncEngine、CloudKit 传输、SyncService |
| `Packages/JingliCore/Sources/JingliAgent/` | 工具目录、OpenAI 兼容 provider、Agent 循环 |
| `iOS/Jingli/` | SwiftUI 界面（今天 / 开启一天 / 计时 / 项目 / 统计 / 设置 / 助手） |
| `iOS/Widget/` | 只读 Widget + Live Activity |
| `iOS/Shared/` | 主 App 与扩展共用的类型 |
| `docs/ios-icloud-design.md` | 同步技术方案 |
| `docs/ios-build-plan.md` | 拆解与进度（含每次验证的记录） |

## 三、跑起来

```bash
# 生成工程
cd iOS && xcodegen generate && cd ..

# 模拟器
xcodebuild -project iOS/Jingli.xcodeproj -scheme Jingli -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/jingli-ios-dd build

# 真机（需要已在 Xcode 登录开发者账号）
xcodebuild -project iOS/Jingli.xcodeproj -scheme Jingli -configuration Debug \
  -destination 'id=<硬件UDID>' -derivedDataPath /tmp/jingli-ios-dd -allowProvisioningUpdates build

xcrun devicectl device install app --device <UDID> /tmp/jingli-ios-dd/Build/Products/Debug-iphoneos/Jingli.app
xcrun devicectl device process launch --device <UDID> --console --terminate-existing \
  com.freedom-shen.jingli.ios -- -ckcheck
```

真机截图（`idevicescreenshot` 在 iOS 17+ 失效）。关闭系统通知弹窗：`DEVICECTL_CHILD_JINGLI_NO_NOTIFICATIONS=1` 放在 `devicectl` 前面。

```bash
pymobiledevice3 developer dvt screenshot --udid <硬件UDID> --userspace shot.png
```

## 四、调试启动参数

`devicectl` 传带前导 `-` 的参数时，bundle id 后要加 `--`。

| 参数 | 作用 |
|---|---|
| `-demo` / `-demo-fresh` | 灌一份演示数据（模拟器用） |
| `-screen=今天\|项目\|统计\|设置` | 直接打开某个 Tab（截图用） |
| `-preselect` | 开启一天页面预选几项 |
| `-autofocus` | 直接起一轮 25 分钟 |
| `-fasttimer` | 起一个 6 秒的番茄，用来验证结算弹窗 |
| `-addsheet` / `-detail` | 直接打开新建任务 / 任务详情 |
| `-voice` | 直接进语音识别 |
| `-asrfile` | 用打包的中文音频跑识别自检 |
| `-ckcheck` | CloudKit 自检：账号 → 建 zone → 写默认 zone → 推一条 → 拉回来 |
| `-cksync` | 用真实库跑一次完整同步 |
| `-cktwodevice` | 用第二个内存库（独立 deviceID）验证双向收敛 |
| `-syncwiring` | 验证「写入 → 去抖 → 自动推送」这条真实路径 |
| `-cleanprobe` / `-cleandemo` | 清掉自检 / 演示数据 |
| `-seedcheck` | 写入带 `·演示` 标记的演示任务 |
| `-startday` / `-endfocus` | 自动开启一天 / 结束当前计时（截图用） |
| `-ask=…` | 打开助手并直接发送这句话 |

环境变量 `JINGLI_NO_NOTIFICATIONS=1` 关闭真实通知（截图/自检时用，避免系统弹窗挡住界面）。

## 五、验证到什么程度

| 能力 | 证据 |
|---|---|
| CloudKit 往返 | 真机日志 `zone created / push accepted=1 / pull count=1 foundOwn=true` |
| 双向收敛 | 真机日志 `B pulled=28 applied=28 看到A的=true`、`A 看到B的=true` |
| 自动同步 | 真机日志 `写入后待推送=9 → 8 秒后待推送=0` |
| 失败重试 | 单测：失败后 pending 保留，退避重试成功后对端能收到 |
| 多设备合并 | 单测：不同字段都保留 / 同字段收敛 / 删除传播 |
| 模型操作数据库 | 真机 + 单测：模型调 `task_add` 落一条 temporary、estimate=5 |
| 界面配置 Key 后可用 | 模拟器实点：设置填 Key → 助手问「今天还剩几件」→ 模型答「还剩 1 件：Refactor module」并调 `today_get` |
| 历史回顾 | 单测：模型调 `stats_history` 返回按天数据；统计页入口带预填问题 |
| 中文语音识别 | 真机日志：TTS 音频 → `帮我加一个临时任务评审设计稿大概两个钟` |
| 语音落在录入口 | 新建任务页标题栏有麦克风（`addtask.mic`），说完直接成为标题 |
| ASR 原文喂模型 | 单测：无标点原文 → 仍只落一条任务、预估正确 |
| Widget / App Group | 共享容器里直查 sqlite；Widget 编译嵌入安装成功 |

**没验证的**：真人对着麦克风说话（硬件采集）、动态岛渲染（模拟器不绘制，真机未单独确认）、真机上的完整点击流程。

## 六、已知问题

- Widget 需要在桌面手动添加（命令行加不了）
- Mac 端还没接同步（Mac 目前 ad-hoc 签名、无 team，接 CloudKit 要改打包流程）

## 七、数据与隐私

- 数据库在 App Group 容器：主 App 与 Widget 共用
- 同步只走用户自己的 iCloud 私有库，没有第三方服务
- 仓库里没有任何密钥；模型 Key 存 iOS Keychain，调试可用环境变量注入
