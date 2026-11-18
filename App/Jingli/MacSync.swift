import Foundation
import JingliCore
import JingliSync

/// Mac 端的同步调度。
///
/// 不在每个写操作后面挂回调（Mac 端写入路径太多，包括 CLI / Agent socket 直连数据库），
/// 改成**轮询待推送数量**：每 3 秒看一眼 `sync_change` 里有没有没推的，有就触发同步。
/// 回到前台时再主动拉一次远端。
@MainActor
final class MacSync {
    static let shared = MacSync()
    static let containerID = "iCloud.com.freedom-shen.jingli"

    private var service: SyncService?
    private var store: SyncStore?
    private var lastCheck = Date.distantPast
    private var lastPull = Date.distantPast
    private var lastReportedPending = -1

    private init() {}

    func configure(database: JingliDatabase) {
        guard service == nil else { return }
        let store = SyncStore(database: database)
        self.store = store
        service = SyncService(
            store: store,
            engine: SyncEngine(
                store: store,
                transport: CloudKitTransport(config: .init(containerIdentifier: Self.containerID))
            ),
            debounceSeconds: 1.5
        )
        // 启用同步之前就有的任务不会自己进队列，第一次跑时补一遍
        let backfilled = (try? store.backfillIfNeeded()) ?? 0
        if backfilled > 0 {
            NSLog("[SYNC] 首次补录变更=\(backfilled)")
        }
        // 换了 CloudKit 环境后，旧游标和「已推送」标记全部作废，整库重推一次。
        if ProcessInfo.processInfo.arguments.contains("-syncreset") {
            let requeued = (try? store.resetForNewEnvironment()) ?? 0
            NSLog("[SYNC] 环境重置：游标清空、重推变更=\(requeued)")
        }
        NSLog("[SYNC] 已配置，待推送=\((try? store.pendingCount()) ?? -1)")
    }

    /// 由 AppModel 每 0.5 秒调用一次，内部节流。
    func tick() {
        guard let store, let service else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCheck) > 3 else { return }
        lastCheck = now
        let pending = (try? store.pendingCount()) ?? 0
        if pending != lastReportedPending {
            lastReportedPending = pending
            NSLog("[SYNC] 待推送=\(pending)")
        }
        if pending > 0 {
            _Concurrency.Task { await service.noteLocalChange() }
            return
        }
        // 没有待推送也要定期拉取：App 在后台时不会触发 didBecomeActive，
        // 只靠激活事件会一直收不到对端的新数据。
        if now.timeIntervalSince(lastPull) > 15 {
            lastPull = now
            syncNow()
        }
    }

    /// 回到前台 / 手动触发：立即推拉一次。
    func syncNow() {
        guard let service else { return }
        _Concurrency.Task {
            let status = await service.syncNow()
            NSLog("[SYNC] 同步完成 待推送=\(status.pending) 上次=\(String(describing: status.lastSyncAt)) 错误=\(String(describing: status.lastError))")
        }
    }
}
