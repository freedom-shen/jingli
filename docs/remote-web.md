# 手机网页（远程加任务）

状态：v1（2026-11-15）。在 Mac 上开一个本地 HTTP 服务，手机通过 **Tailscale** 或家庭局域网打开一个网页，就能看今天、加临时任务、勾完成。

## 为什么是这个方案

- 不做微信小程序：不用注册账号、不用云开发、不用备案、不用域名。
- 不做公网服务：服务只监听本机网卡，Tailscale 负责把手机和 Mac 放进同一个虚拟局域网（WireGuard 加密）。
- 写操作复用现有 `AgentCommandRouter`，和 CLI / Agent 走同一套业务规则，并在 `agent_event` 里留审计记录（`actor = web`）。

## 边界（v1 只做这些）

- ✅ 看今天：任务、项目、完成状态、今日番茄数
- ✅ 加临时任务（自动进今日计划，不占主线 4 个名额）
- ✅ 勾完成 / 取消完成
- ✅ 今天还没开始时，「开启今天」
- ❌ 不跑番茄计时、不改项目、不删除、不调设置

## 准备：Tailscale（一次性）

1. **Mac**：从 [tailscale.com](https://tailscale.com/download) 或 App Store 安装 Tailscale，用你的账号登录（GitHub / Google / Apple 都行）。
2. **iPhone**：App Store 安装 Tailscale，登录**同一个账号**。
3. 两端都打开开关；Mac 菜单栏 Tailscale 里确认设备已连接。
4. 记下 Mac 的 Tailscale 地址（形如 `100.x.y.z`）：Tailscale 菜单栏 → 本机 IP；或 `ifconfig | grep "inet 100\."`。

> 不用 Tailscale 也能用：Mac 和手机连同一个 Wi‑Fi 时，设置页会出现「局域网」地址。缺点是出门就断了。

## Mac 侧

1. 打开「精力管理 → 设置 → 手机网页（远程加任务）」。
2. 打开开关；地址列表会出现：
   - `Tailscale`：`http://100.x.y.z:8787/?t=<token>`
   - `局域网 en0`：`http://192.168.x.y:8787/?t=<token>`
3. 点「复制」复制 Tailscale 那条链接。

## 手机侧

1. 用 Safari 打开复制的链接（**只在首次需要带 token**，之后手机会记住）。
2. 可以「分享 → 添加到主屏幕」，当小 App 用。
3. 页面功能：
   - 顶部：日期、周几、今日番茄数、已完成数；
   - 列表：点一行 = 勾完成 / 取消完成；
   - 底部输入框：输入标题回车 = 加临时任务并进今天；
   - 今天没开始时会出现「开启今天」按钮。

## 安全

- 链接里的 `token` 等同密码：拿到它的人能读写你的任务。**不要转发**；怀疑泄露就点「重新生成链接」，旧链接立即失效。
- 服务只监听局域网/Tailscale，不碰公网、不需要路由器端口映射。
- 经 Tailscale 访问时流量是 WireGuard 加密的；纯局域网访问是明文 HTTP，只建议在家里 Wi‑Fi 用。
- token 存在本地 `setting` 表（设备本地，不参与同步），仓库里没有任何密钥。

## 故障排查

| 现象 | 处理 |
|---|---|
| 设置页看不到 Tailscale 地址 | Mac 端 Tailscale 没登录/没连上；确认 `ifconfig` 里有 `100.x` 地址后点「刷新地址」 |
| 手机打不开 | 手机 Tailscale 没开；或 Mac 睡眠/关机。先在同一 Wi‑Fi 下试「局域网」链接 |
| 端口被占用 | 会自动退到系统分配的端口，链接端口跟着变；点「复制」拿新链接 |
| 页面显示「还没配对」 | 链接没带 token：回设置页重新复制 |
| macOS 防火墙弹窗 | 允许「精力管理」接受传入连接 |

## 实现位置

- `Packages/JingliCore/Sources/JingliCore/RemoteWebServer.swift`：HTTP 服务、token 鉴权、API 路由
- `Packages/JingliCore/Sources/JingliCore/RemoteWebPage.swift`：内联单页（无 CDN、无外部依赖）
- `App/Jingli/RemoteWebController.swift`：开关 / 端口 / token / 地址枚举
- `App/Jingli/Features/Settings/RemoteWebSettingsContent.swift`：设置页区块
- 测试：`Packages/JingliCore/Tests/JingliCoreTests/RemoteWebServerTests.swift`
