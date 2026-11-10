# LeanCloud 同步方案

状态：v2 设计稿（2026-11-05）。P1 本地变更层已实现；P2 起开始接云端。

对应任务：「JingLi 工具小程序化 · 数据库建立、数据库同步」。

## 1. 背景与目标

- Jingli 目前是纯本地应用：数据存每台 Mac 各自的 SQLite（`~/Library/Application Support/Jingli/jingli.sqlite`）。
- 已经有**多台 Mac** 在用，计划增加**微信小程序**端（体验版自用）。
- 目标：
  1. 把现有本地数据**一次性迁移**到远端；
  2. 日常**双向同步**：任何一端的改动最终一致地出现在其他端；
  3. 远端用 **LeanCloud 开发版**（3 万请求/天、1GB、3 并发，个人用量足够）；
  4. 仓库保持可开源：AppID / Key / 密码不进仓库。

非目标（v1）：

- 不做实时推送（定时 + 事件触发即可）；
- 不在小程序里跑番茄计时（小程序切后台会被挂起）；
- 不同步 `setting`、`task_order`、`agent_event` 等设备本地状态；
- 不做按设备/项目的选择性同步（v1 所有设备共享一份数据）。

## 2. 总体架构

```
Mac A (SQLite) ─┐
Mac B (SQLite) ─┼─► LeanCloud（append-only 变更日志）◄─ 微信小程序
Mac C (SQLite) ─┘
```

- **本地 SQLite 仍是主工作区**：所有功能照旧读写本地库，不依赖网络。
- **LeanCloud 只存变更，不做合并**：云端是 append-only 的 `JingliChange`，谁都不覆盖谁。
- **每个端自己归并**：按 `(entity, entityId, field)` 取 `rev` 最大的值，物化到 SQLite / 小程序 storage。
- 同步引擎是独立模块（`SyncStore`），业务写入通过 SQLite trigger 自动进入变更日志，不需要改 30 多个写入点。

为什么不用“云端当前行 + 整行 LWW”：

- 整行 LWW 会让 A 改备注、B 勾完成时丢掉一边；
- 多端同时写云端同一行需要 read-modify-write，没有事务时仍会丢更新；
- append-only 日志天然幂等、可重放，冲突只在客户端按字段解决。

## 3. 同步范围

| 本地表 | 是否同步 | 合并方式 |
|---|---|---|
| `project` | ✅ | 字段级 LWW；删除墓碑 |
| `task` | ✅ | 字段级 LWW；删除墓碑 |
| `day_plan` | ✅ | 字段级 LWW；删除后更高 rev 可重建 |
| `day_plan_task` | ✅ | 按 `(date, taskId)` 成员合并；`__present` 加/删 |
| `focus_session` | ✅ | append-only，按 id 合并 |
| `focus_session_task` | ✅ | `__present` + share |
| `task_completion` | ✅ | 按 id 合并；撤销用 `__deleted` |
| `setting` | ❌ | 计时器、`last_seen_day`、`focus_streak` 等设备本地状态 |
| `task_order` | ❌ | v1 手动排序保持设备本地 |
| `agent_event` | ❌ | 本地审计日志 |

补充：

- `task.sort_order` / `project.sort_order` 不同步，排序按 `created_at` 等本地派生。
- `task.created_at` 同步；`task.planned_date` 同步，但**过去的日期会被接收端丢弃**（见 5.4）。
- `focus_session` 的完成用 UPSERT 写入，不再 `INSERT OR REPLACE`，避免产生“先删后建”的日志。

## 4. 本地数据模型（已实现）

迁移 `v6_sync` 新增：

### 4.1 `sync_change`

```sql
seq INTEGER PRIMARY KEY AUTOINCREMENT,
entity TEXT, entity_id TEXT, field TEXT,
value TEXT,          -- JSON 标量/对象
ms INTEGER,          -- 物理毫秒
device_id TEXT,
created_at TEXT,     -- ISO8601
pushed_at TEXT,      -- NULL = 待推送
rev TEXT GENERATED AS printf('%016llx-%s-%016llx', ms, device_id, seq)
```

- `rev` 是 HLC：毫秒 + 设备 + 本地序号，字符串比较即顺序。
- 每条记录只描述一个字段；`value='null'` 表示清空。
- `__deleted`：实体删除墓碑；`__present`：成员是否存在（今日计划 / 番茄任务关联）。

### 4.2 其他表

| 表 | 用途 |
|---|---|
| `sync_field_rev` | `(entity, entity_id, field) -> rev`，字段级 LWW 的当前版本 |
| `sync_tombstone` | `(entity, entity_id) -> rev`，删除终态，防止旧变更复活 |
| `sync_meta` | `device_id`、`suppress` 等运行标记 |
| `sync_clock` | `max_ms`，本地写入的 HLC 下界 |

### 4.3 Trigger

- 对 `project` / `task` / `day_plan` / `day_plan_task` / `focus_session` / `focus_session_task` / `task_completion` 安装 INSERT / UPDATE / DELETE trigger。
- INSERT 逐字段写一条变更；UPDATE 只写真正变化的字段；DELETE 写 `__deleted` 或 `__present=false`。
- `setting` / `task_order` / `agent_event` 不装 trigger。
- `sync_change` 的 AFTER INSERT trigger 负责更新 `sync_field_rev`、`sync_tombstone`、`sync_clock`。
- `suppress` 标记用于两类写入：`rollover`（本地派生，不产生变更）和 apply 远端变更（不回写）。

### 4.4 今日计划的 diff 写入

`saveDaySelection` / `startDay` 不再“删光当天 + 全量重插”，而是只删除真正移除的、只插入真正新增的、只更新 lane 变化的行。

否则同步层无法表达“谁删了哪一条”，并集会把它加回来。

### 4.5 已实现的测试

`Packages/JingliCore/Tests/JingliCoreTests/SyncTests.swift`：

- 创建 / 更新 / 删除的变更捕获；
- rollover 不产生变更；
- 今日计划只发新增 / 移除；
- `setting` / `task_order` 不被捕获；
- 番茄完成不产生“先删后建”；
- 双端不同字段并发合并；
- 删除胜过离线旧编辑；
- 删项目后任务回到未分类；
- 今日计划并集 + 移除传播；
- rollover 不覆盖另一台今天的计划；
- 过去的 `planned_date` 被丢弃。

## 5. 同步协议

### 5.1 推送

```
pending = SELECT * FROM sync_change WHERE pushed_at IS NULL ORDER BY seq
POST /1.1/batch  (每批 ≤ 100 条 JingliChange)
→ 成功后 UPDATE sync_change SET pushed_at = now()
```

- 云端对象字段：`changeID`（`deviceID:seq`）、`entity`、`localId`、`field`、`value`、`rev`、`ms`、`deviceID`、`createdAt`（服务端生成）。
- 重试可能产生重复行；客户端按 `changeID` 去重，重复是幂等的。
- 只有本地变更需要推送；远端 apply 不写 `sync_change`。

### 5.2 拉取

```
GET /1.1/classes/JingliChange
    ?where={"createdAt":{"$gt": cursor - 2min}}
    &order=createdAt&limit=1000
→ 按 changeID 去重 → SyncStore.apply(changes)
→ cursor = max(createdAt)
```

- **游标用 LeanCloud 服务端 `createdAt`**，不用本地毫秒。
- 2 分钟重叠覆盖分页/同秒写入；`changeID` 幂等去重。
- `rev` 只用于字段冲突排序。

### 5.3 新设备 / 小程序首屏

- Mac 定期上传 `JingliSnapshot`：当前任务、项目、今日计划、最近番茄，以及 `snapshotRev`（已包含的最大 rev）。
- 新设备先拉最新快照，再拉 `rev > snapshotRev` 的变更；不需要重放全部历史。
- 小程序本地用 `wx.setStorageSync` 缓存物化状态；`onShow` 增量拉取。

### 5.4 合并规则

- **字段级 LWW**：同一个字段取 `rev` 最大者；不同字段互不覆盖。
- **删除**：
  - `task` / `project` / `focusSession` / `taskCompletion`：`__deleted` 是终态，旧字段变更不能复活；要恢复请新建。
  - `day_plan`：`__deleted` 参与 rev 比较，之后更高 rev 的字段可以重建。
  - `day_plan_task` / `focus_session_task`：用 `__present=false` 移除，之后更高 rev 的 `__present=true` 可以重新加入。
- **今日计划**：按成员合并。A 加 t1、B 加 t2 → 并集；A 移除 t1 → `__present=false` 传播，B 不会再加回来。
- **rollover**：本地派生，不产生同步变更；接收端丢弃 `planned_date < 今天` 的远端变更。这样离线几天的机器既不会清掉别人的今天，也不会被旧计划拉回。
- **引用完整性**：删除 project 时，把任务的 `project_id` 置空并作为 task 的字段变更传播；不能只依赖 SQLite 外键。

## 6. 首次迁移（必须先拍板）

两台 Mac 上各自创建的同名任务 UUID 不同，任何同步算法都无法判断它们“是同一件事”。首次迁移前必须选一条路：

1. **canonical source（推荐）**：选一台 Mac 作为基准；其他机器整库备份（复制 `jingli.sqlite`，不要用 JSON 备份，JSON 不含番茄历史）→ 清空数据库 → 全量拉取。
2. **一次性去重合并**：保留两边数据，按标题 / 项目 / 日期列出疑似重复，人工合并 ID 后再上云。工作量大一截，只在两边都有大量独有数据时做。

注意：

- 不要在已同步的设备上随意导入旧 JSON 备份：`BackupService.importJSON` 会按 id 覆盖 `planned_date/done/note`，会再次制造“数据混”。
- 迁移完成后，云端应能按 `localId` 查到与本地一致的条数；先在两台机器的测试库跑，再切真实数据。

## 7. 账号、配对与安全

**原则：仓库里只有代码，没有凭证。**

- 不需要微信登录 / openid。v1 使用**一个同步账号 + 一次性配对**：
  1. Mac A 生成随机强密码的 LeanCloud `_User`；
  2. 所有 `JingliChange` / `JingliSnapshot` 行 ACL 只给这个用户读写；
  3. 设置页显示一次性配对串/二维码（`appId` + `appKey` + `serverURL` + 同步账号 + 密码）；
  4. Mac B / 小程序扫一次或粘一次，之后存 Keychain / `wx.setStorageSync`，每次启动静默登录，没有登录界面。
- AppKey 放在小程序包里是正常的（它本来就是客户端 key）；真正的秘密是同步账号密码和 ACL。AppSecret 不进仓库、不进小程序。
- 想吊销设备：改同步账号密码，并在 LeanCloud 控制台清理旧 `_Session`。以后要按设备吊销，再上 LeanCloud Role + 微信 openid。

## 8. LeanCloud / 微信小程序的现实约束

- **免费额度**：开发版 3 万 API 请求/天、1GB 存储、3 并发；2–3 台 Mac + 一个小程序日常用远低于限额。需要实名认证。
- **域名**：LeanCloud 国内版数据存储要求绑定**已备案域名**；测试/共享域名可用，但官方明确说可能回收、无可用性保证。体验版自用可以先跑测试域名；长期日用建议买域名做备案（几十元/年 + 1–3 周）。
- **小程序合法域名**：小程序后台要把该域名加入 `request 合法域名`；体验版可以开开发调试绕过校验，但不适合长期日用。
- **小程序备案**：体验版一般可以先跑；正式发布前要完成小程序备案（以公众平台提示为准）。个人主体做工具类、只自己用没有问题。
- **小程序能力边界**：只做“看今天 / 快速加任务 / 勾完成 / 改备注 / 看最近专注记录”；不跑计时器。

## 9. 实施步骤

1. **P1 – 本地变更层（已完成）**：v6 迁移、trigger、`sync_field_rev`、`sync_tombstone`、`SyncStore.apply`、rollover 静默、今日计划 diff、双端单测；`swift test` 95/95。
2. **P2 – Mac 同步引擎**：`SyncConfig`（Keychain + 仓库外配置）、LeanCloud REST（URLSession，不引 SDK）、登录、pull/push、`JingliSnapshot`、设置页状态/“立即同步”。
3. **P3 – 迁移与双机验证**：canonical Mac、全量推送、两台 Mac 对照（改标题 / 改备注 / 删除 / 离线跨天 / 同时排今天）。
4. **P4 – 小程序 MVP**：今日列表、加临时任务、勾完成、备注；一次配对后静默同步；首屏快照。
5. **P5 – 打磨**：同步日志/冲突提示、墓碑清理、快照压缩（可选）、多设备吊销。

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| LeanCloud 免费版配额/可用性 | 本地优先；批量写 + 增量拉；设置页显示上次同步时间 |
| 测试域名被回收 | `serverURL` 可配置；长期日用绑定已备案域名 |
| 双端时钟偏差 | HLC + 服务端 `createdAt` 游标；重叠拉取 |
| 删除 vs 离线编辑 | task/project 删除终态；要恢复新建 |
| 首次迁移产生重复任务 | 先选 canonical Mac，其他机器备份后重置；或一次性去重 |
| 旧备份导入覆盖新数据 | 已同步设备上禁止直接导入旧 JSON；只用于迁移/灾难恢复 |
| AppKey/密码泄露 | ACL 只授权同步账号；AppKey 可公开，密码存 Keychain/微信 storage；可改密 |
