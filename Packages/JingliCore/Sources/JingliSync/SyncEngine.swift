import Foundation
import JingliCore

/// 一次同步 = 推待发 → 拉增量 → 应用 → 重放卡住的。
/// 不持有 UI、不决定「什么时候同步」，那是 App 的事。
public actor SyncEngine {
    private let store: SyncStore
    private let transport: SyncTransport

    public init(store: SyncStore, transport: SyncTransport) {
        self.store = store
        self.transport = transport
    }

    @discardableResult
    public func syncOnce(batchSize: Int = 200) async throws -> SyncReport {
        // 1) 推送：按批发，直到没得发或者服务端拒收
        var pushed = 0
        while true {
            let pending = try store.pendingChanges(limit: batchSize)
            guard !pending.isEmpty else { break }
            let accepted = try await transport.push(pending)
            let ok = pending.filter { accepted.contains($0.changeID) }
            guard !ok.isEmpty else { break }
            try store.markPushed(ok)
            pushed += ok.count
            if ok.count < pending.count { break }
        }

        // 2) 拉取 + 合并
        let (changes, cursor) = try await transport.pull(cursor: try store.syncCursor())
        let skipped = try store.apply(changes)
        try store.setSyncCursor(cursor)

        // 3) 之前卡在外键上的，现在再试一次
        let retried = try store.retryPending()

        return SyncReport(
            pushed: pushed,
            pulled: changes.count,
            applied: changes.count - skipped.count,
            skipped: skipped.count,
            retried: retried
        )
    }
}
