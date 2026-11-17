import Foundation
import JingliCore

/// 「边改边同步」的调度层：本地写完之后去抖几秒跑一次，失败不阻塞写入。
public actor SyncService {
    public struct Status: Sendable, Equatable {
        public let pending: Int
        public let lastSyncAt: Date?
        public let lastError: String?
        public let isSyncing: Bool
    }

    private let store: SyncStore
    private let engine: SyncEngine
    private let debounceSeconds: Double
    private let retryBaseSeconds: Double

    private var debounceTask: _Concurrency.Task<Void, Never>?
    private var retryTask: _Concurrency.Task<Void, Never>?
    private var retryAttempt = 0
    private var lastSyncAt: Date?
    private var lastError: String?
    private var syncing = false

    public init(
        store: SyncStore,
        engine: SyncEngine,
        debounceSeconds: Double = 3,
        retryBaseSeconds: Double = 2
    ) {
        self.store = store
        self.engine = engine
        self.debounceSeconds = max(0, debounceSeconds)
        self.retryBaseSeconds = max(0, retryBaseSeconds)
        self.lastSyncAt = try? store.lastSyncAt()
    }

    /// 本地有写入时调用（可以高频，去抖兜住）。
    public func noteLocalChange() {
        debounceTask?.cancel()
        let delay = debounceSeconds
        debounceTask = _Concurrency.Task { [weak self] in
            if delay > 0 {
                try? await _Concurrency.Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    /// 立即同步（下拉刷新 / 回到前台 / 手动按钮）。
    @discardableResult
    public func syncNow() async -> Status {
        debounceTask?.cancel()
        await performSync()
        return makeStatus()
    }

    public func status() -> Status { makeStatus() }

    private func performSync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }

        do {
            _ = try await engine.syncOnce()
            lastSyncAt = Date()
            lastError = nil
            retryAttempt = 0
            retryTask?.cancel()
            retryTask = nil
            try? store.setLastSyncAt(lastSyncAt)
        } catch {
            lastError = error.localizedDescription
            scheduleRetry()
        }
    }

    /// 失败后指数退避重试（2s / 4s / 8s … 最多 60s），成功即清零。
    private func scheduleRetry() {
        retryTask?.cancel()
        let delay = retryBaseSeconds > 0
            ? min(60, retryBaseSeconds * pow(2, Double(retryAttempt)))
            : 0
        retryAttempt += 1
        guard delay > 0 else { return }
        retryTask = _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.performSync()
        }
    }

    private func makeStatus() -> Status {
        Status(
            pending: (try? store.pendingCount()) ?? 0,
            lastSyncAt: lastSyncAt,
            lastError: lastError,
            isSyncing: syncing
        )
    }
}
