# LeanCloud 同步方案

状态：设计稿（v1，2026-11-02）。对应任务：「JingLi 工具小程序化 · 数据库建立、数据库同步」。

## 1. 背景与目标

- Jingli 目前是纯本地应用：数据存每台 Mac 各自的 SQLite（`~/Library/Application Support/Jingli/jingli.sqlite`）。
- 已经有**多台 Mac** 在用，计划增加**微信小程序**端（体验版自用）。
- 目标：
  1. 把现有本地数据**一次性迁移**到远端；
  2. 日常**双向同步**：任何一端的改动最终一致地出现在其他端；
  3. 远端选型已定 **LeanCloud 开发版**（免费额度约 1GB 存储 / 每日数万次请求）；
  4. 仓库**保持可开源**：任何 AppID / Key / 密码不进仓库。

## 2. 总体架构

```
Mac A (SQLite, 本地为主) ─┐
Mac B (SQLite)          ─┼─► LeanCloud（单一数据源 hub）◄─ 微信小程序（SDK 直连）
Mac C (SQLite)          ─┘
```

- **本地 SQLite 仍是主工作区**：App 的所有功能照旧读写本地库，不依赖网络。
- **LeanCloud 是同步 hub**：不承载业务查询，只存记录与变更。
- 小程序端直接读写 LeanCloud（官方 `leancloud-storage` SDK），天然与 Mac 端一致。
- 同步引擎是独立模块（`JingliSync`），对现有代码的侵入仅限于「记录本地变更时间戳」。

## 3. 同步范围

| 本地表 | 是否同步 | 说明 |
|---|---|---|
| `project` | ✅ | 项目 |
| `task` | ✅ | 任务（含 plannedDate，即「今天」的来源） |
| `day_plan` / `day_plan_task` | ✅ | 开一天状态与当日选择 |
| `focus_session` / `focus_session_task` | ✅ | 番茄记录（append-only，天然无冲突） |
| `task_order` | ✅ | 手动排序 |
| `setting` | 部分 | 只同步 `day_start_hour` 等用户偏好 |
| `agent_event` | ❌ | 本地审计日志，不同步 |

不做实时推送，**定时 + 事件触发**的批量同步即可（个人工具，秒级延迟无意义）。

## 4. 云端数据模型

每个本地表对应一个 LeanCloud class（`Project` / `Task` / `PomodoroRecord` / `DayPlan` / `TaskOrder`），字段要点：

| 字段 | 用途 |
|---|---|
| `localId` | 本地 UUID，**业务主键**。本地库结构不变，跨端引用（如 task.projectId）都存 localId |
| `rev` | 自定义毫秒时间戳，每次写入 = 当前本地毫秒。同步游标与冲突判定都基于它 |
| `deleted` | 软删除墓碑（true = 已删除） |
| `ACL` | 行级权限：仅同步账号可读写 |

为什么用 `rev` 而不是 LeanCloud 自带 `updatedAt`：其日期精度为**秒**，同秒内多次写无法排序；`rev` 是毫秒整数，可比较、可做增量游标。

## 5. 同步协议

### 5.1 首次迁移（存量数据上云）

- 本地全量读取 → 逐条转 `localId + rev + deleted=false` 推到 LeanCloud。
- **幂等**：推送前按 `localId` 查询，已存在则比较 `rev`，云端更新才覆盖。
- 迁移完成的判定：本地所有表推完且拉回校验条数一致。迁移脚本做成 App 内「立即同步」的首跑，不单独写一次性代码。

### 5.2 增量同步（每个客户端循环执行）

```
pull:  GET classes/Task?where={"rev":{"$gt":lastPulledRev}}&limit=100&order=rev
       → 应用到本地（见 5.3 合并规则）
push:  本地 rev > lastPushedRev 的行 → POST /1.1/batch 批量写云端
       → 成功后更新 lastPushedRev
```

- 每表各自有 `lastPulledRev` / `lastPushedRev`，存本地 `sync_state` 表。
- 触发时机：App 启动、手动「立即同步」、有本地写操作后延迟 30 秒、每 5 分钟兜底。
- 失败静默重试（下次触发自然重做），同步状态在设置页展示。

### 5.3 合并与冲突（多 Mac 语义）

- **插入类数据**（focus_session / task 的创建）：无冲突，localId 相同即同一条。
- **可变字段**（task.title / note / estimate / done、project.name）：整行 LWW（last-write-wins），`rev` 大者胜。个人多端场景下同秒改同一条的概率极低，LWW 足够；被覆盖方在设置页同步日志里留一行提示。
- **删除**：墓碑传播。`deleted=true` 的行以更高优先级胜过未删除行（删除是明确意图）。本地收到墓碑后标记并保留 30 天再物理清理，防止离线端漏拉导致「复活」。
- **day_plan_task**（当日选择）：按 `(date, taskId)` 合并，两侧并集去重——白天在 A 加了一件、晚上 B 加另一件，第二天两件都在。
- **task_order**：不合并，整表 LWW（最后拖动的人说了算）。

### 5.4 小程序端

- 直接读写 LeanCloud（SDK 或 REST），不经过任何 Mac。
- 与 Mac 的合并规则同上；小程序不做本地持久层，离线不缓存写操作。

## 6. Key 与安全（开源前提）

**原则：仓库里只有代码，没有凭证。**

1. AppID / AppKey / 账号密码存放在**仓库外**的本地配置：
   - `~/Library/Application Support/Jingli/sync.plist`（该目录整体被 `.gitignore` 排除，且本就不在仓库内）；
   - 密码优先存 macOS Keychain。
2. 代码里通过 `SyncConfig.load()` 读取；配置缺失时同步功能整体禁用并在设置页提示，App 其余功能不受影响。
3. **文档与提交里只允许出现占位符**（`<APP_ID>` / `<APP_KEY>`），本方案即示范。
4. 纵深防御（即使 Key 泄露也不丢数据）：
   - 所有数据行挂 ACL，仅同步账号（LeanCloud `_User`）可读写；客户端启动时账号密码登录（密码在 Keychain）；
   - AppKey 泄露最多消耗免费配额，读不到 ACL 保护的行；
   - LeanCloud 控制台可随时重置 Key。

## 7. 实施步骤

1. **Phase 1 – 配置与骨架**：注册 LeanCloud、建应用；`SyncConfig` / `sync.plist`；`JingliSync` 模块骨架与设置页「同步」区块（状态 + 立即同步按钮）。
2. **Phase 2 – 首次迁移**：全量推送本地数据（幂等），云控制台核对条数。
3. **Phase 3 – 增量同步**：pull/push 循环、sync_state、墓碑与 LWW 合并、单测（合并规则与墓碑传播）。
4. **Phase 4 – 多端验证**：两台 Mac 对照测试（A 改标题 / B 改备注 / C 删除），确认最终一致。
5. **Phase 5 – 小程序**：接 SDK，读同一套 class；同步规则复用。
6. **Phase 6 – 打磨**：同步日志、失败重试提示、墓碑清理任务。

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| LeanCloud 免费版 30 天无请求归档 | 多端日常使用不会触发；仍可在设置页显示「上次同步时间」引起注意 |
| 免费版 QPS / 日请求限额 | 批量 batch 写 + 同步节流；单人远低于限额 |
| 双端同一秒内互改（LWW 丢一侧） | 概率极低；同步日志留痕，重要字段（note）未来可升级为字段级合并 |
| 体验版小程序的合法域名限制 | 体验版开启调试模式（不校验域名）即可；正式上线再走 LeanCloud 商用版域名绑定 |
| 第三方服务不可用 | 本地 SQLite 离线完整可用，云端只是副本；恢复后增量同步自然追平 |
| Key 泄露 | ACL + 账号体系兜底（见第 6 节）；Key 可随时重置 |
