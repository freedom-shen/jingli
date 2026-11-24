import CloudKit
import Foundation
import JingliCore

/// CloudKit 私有库传输层。
///
/// - 自定义 zone（`JingliZone`），每条变更一条记录，recordName = `deviceID:seq`，
///   天然幂等：重复推送只会覆盖同一条记录。
/// - 拉取用 `serverChangeToken` 做增量；token 交给引擎持久化。
/// - 巨量变更靠分批（200 条/批），不依赖单次操作的上限。
public final class CloudKitTransport: SyncTransport, @unchecked Sendable {
    public struct Config: Sendable {
        public var containerIdentifier: String
        public var zoneName: String
        public var batchSize: Int

        public init(
            containerIdentifier: String,
            zoneName: String = "JingliZone",
            batchSize: Int = 200
        ) {
            self.containerIdentifier = containerIdentifier
            self.zoneName = zoneName
            self.batchSize = batchSize
        }
    }

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let batchSize: Int
    private let lock = NSLock()
    private var zoneReady = false

    public init(config: Config) {
        let container = CKContainer(identifier: config.containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: config.zoneName, ownerName: CKCurrentUserDefaultName)
        batchSize = max(1, min(400, config.batchSize))
    }

    // MARK: - push

    public func push(_ changes: [SyncChange]) async throws -> [String] {
        guard !changes.isEmpty else { return [] }
        do {
            return try await performPush(changes)
        } catch {
            throw Self.localize(error)
        }
    }

    /// 把 CloudKit 的英文错误码翻成用户能看懂的话。
    static func localize(_ error: Error) -> Error {
        guard let ck = error as? CKError else { return SyncTransportError.other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated: return SyncTransportError.notAuthenticated
        case .networkUnavailable, .networkFailure: return SyncTransportError.offline
        default:
            return SyncTransportError.other(ck.localizedDescription)
        }
    }

    private func performPush(_ changes: [SyncChange]) async throws -> [String] {
        guard !changes.isEmpty else { return [] }
        try await ensureZone()

        var accepted: [String] = []
        for start in stride(from: 0, to: changes.count, by: batchSize) {
            let batch = Array(changes[start..<min(start + batchSize, changes.count)])
            let records = batch.map { Self.record(for: $0, zoneID: zoneID) }
            let batchStarted = Date()
            let (saveResults, _) = try await Self.withTimeout(seconds: 60) {
                try await self.database.modifyRecords(
                    saving: records,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
            }
            NSLog("[CK] push 批次 \(start / batchSize + 1) 条数=\(batch.count) 用时=\(Int(Date().timeIntervalSince(batchStarted) * 1000))ms")
            if saveResults.values.allSatisfy({ if case .failure = $0 { return true } else { return false } }),
               saveResults.count == batch.count {
                // 整批都被拒：多半是 zone 刚建好还没就绪，等一下重试一次
                try? await _Concurrency.Task.sleep(nanoseconds: 1_200_000_000)
                let retry = try await Self.withTimeout(seconds: 60) {
                    try await self.database.modifyRecords(
                        saving: records,
                        deleting: [],
                        savePolicy: .changedKeys,
                        atomically: false
                    )
                }
                for (recordID, result) in retry.saveResults {
                    switch result {
                    case .success: accepted.append(recordID.recordName)
                    case let .failure(error):
                        if Self.isAlreadySynced(error) { accepted.append(recordID.recordName) }
                        else { NSLog("[CK] push record failed: \(error)") }
                    }
                }
                continue
            }
            for (recordID, result) in saveResults {
                switch result {
                case .success:
                    accepted.append(recordID.recordName)
                case let .failure(error):
                    // 对端已经写过同一条（或服务器版本更高）时也算推送完成，本地不再重试。
                    if Self.isAlreadySynced(error) {
                        accepted.append(recordID.recordName)
                    }
                }
            }
        }
        return accepted
    }

    // MARK: - pull

    public func pull(cursor: String?) async throws -> (changes: [SyncChange], cursor: String?) {
        do {
            return try await performPull(cursor: cursor)
        } catch {
            throw Self.localize(error)
        }
    }

    /// 用 async 版 `recordZoneChanges` 拉增量。
    ///
    /// 早期实现用的是 `CKFetchRecordZoneChangesOperation` 的回调版：在 Production
    /// 环境里它的完成回调根本不触发，continuation 永不 resume，`SyncEngine` 这个
    /// actor 就永久卡住，而 `SyncService` 的 `syncing` 一直为 true，后面每次同步
    /// 都被挡住 —— 日志里只有「同步完成 错误=nil」，同步静默失效。
    private func performPull(cursor: String?) async throws -> (changes: [SyncChange], cursor: String?) {
        try await ensureZone()
        do {
            return try await pullOnce(cursor: cursor)
        } catch {
            // 游标失效 / zone 丢失都属于「增量拉永远拉不动」，以前直接把错误抛给上层，
            // 游标本机还留着 → 每次同步都拿同一个废 token 重试，设备永久收不到任何数据，
            // 界面上只有一行错误。这里退回全量：远端是字段级状态 + rev，重放是幂等的。
            switch Self.pullRecovery(for: error) {
            case .none:
                throw error
            case .fullReload:
                NSLog("[CK] 变更游标已失效，改为全量重拉")
                return try await pullOnce(cursor: nil)
            case .recreateZone:
                NSLog("[CK] 同步 zone 不存在，重建后全量重拉")
                try? await recreateZone()
                return try await pullOnce(cursor: nil)
            }
        }
    }

    private func pullOnce(cursor: String?) async throws -> (changes: [SyncChange], cursor: String?) {
        let started = Date()
        NSLog("[CK] pull 开始 cursor=\(cursor == nil ? "nil" : "有")")

        let outcome = try await Self.withTimeout(seconds: 120) {
            var collected: [SyncChange] = []
            var current = cursor.flatMap(Self.decodeToken)
            var more = true
            var rounds = 0
            while more, rounds < 200 {
                rounds += 1
                let batch = try await self.database.recordZoneChanges(
                    inZoneWith: self.zoneID,
                    since: current
                )
                for (_, result) in batch.modificationResultsByID {
                    if case let .success(modification) = result,
                       let parsed = Self.change(from: modification.record) {
                        collected.append(parsed)
                    }
                }
                current = batch.changeToken
                more = batch.moreComing
            }
            return (collected.sorted { $0.seq < $1.seq }, current.flatMap(Self.encodeToken))
        }

        NSLog("[CK] pull 结束 用时=\(Int(Date().timeIntervalSince(started) * 1000))ms 记录=\(outcome.0.count)")
        return outcome
    }

    // MARK: - 超时

    /// 给没有内建超时的 async API（`modifyRecords`）套一层超时。
    ///
    /// CloudKit 偶尔会既不回调也不报错，调用方就会永久挂起：`SyncService` 里的
    /// `syncing` 一直为 true，之后每次同步都被挡住，日志里却只有「同步完成 错误=nil」。
    enum TimeoutError: Error, LocalizedError {
        case exceeded(Int)

        var errorDescription: String? {
            switch self {
            case let .exceeded(seconds): return "CloudKit 请求超过 \(seconds) 秒没有响应"
            }
        }
    }

    static func withTimeout<T: Sendable>(
        seconds: Int,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                throw TimeoutError.exceeded(seconds)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw TimeoutError.exceeded(seconds)
            }
            return first
        }
    }

    // MARK: - zone

    private func ensureZone() async throws {
        guard needsZoneCreation() else { return }
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
            // 新建 zone 后立刻写入偶尔会被服务端拒绝，给它一点时间
            try? await _Concurrency.Task.sleep(nanoseconds: 800_000_000)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // zone 已存在（CloudKit 对重复创建返回 serverRecordChanged），继续
        }
    }

    /// 强制重建 zone：服务端把 zone 清掉（换环境 / 后台清理）后 `zoneNotFound`，
    /// 只重建 zone 不动其它状态，然后让调用方退回全量拉。
    private func recreateZone() async throws {
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch let error as CKError where error.code == .serverRecordChanged {
            // 已存在，忽略
        }
        try? await _Concurrency.Task.sleep(nanoseconds: 800_000_000)
    }

    /// 返回 true 表示需要建 zone；同时把标记置上，避免并发重复创建。
    private func needsZoneCreation() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if zoneReady { return false }
        zoneReady = true
        return true
    }

    private static func isAlreadySynced(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .serverRecordChanged || ckError.code == .batchRequestFailed
    }

    /// 增量拉失败后的自恢复动作。
    enum PullRecovery: Equatable {
        /// 不是可自愈的错误，照常抛给上层（网络、账号、超时…）。
        case none
        /// serverChangeToken 过期：丢掉游标全量拉一遍。
        case fullReload
        /// 服务端没有这个 zone（换环境 / 被清理）：重建后全量拉。
        case recreateZone
    }

    static func pullRecovery(for error: Error) -> PullRecovery {
        if isTokenExpired(error) { return .fullReload }
        if isZoneMissing(error) { return .recreateZone }
        return .none
    }

    /// 游标失效（含 partialFailure 里包着的那个）。
    static func isTokenExpired(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .changeTokenExpired { return true }
        guard ckError.code == .partialFailure else { return false }
        let nested = Array((ckError.partialErrorsByItemID ?? [:]).values)
        return nested.contains { ($0 as? CKError)?.code == .changeTokenExpired }
    }

    /// zone 在服务端不存在（比如换了环境、或从没建过）。
    static func isZoneMissing(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .zoneNotFound { return true }
        guard ckError.code == .partialFailure else { return false }
        let nested = Array((ckError.partialErrorsByItemID ?? [:]).values)
        return nested.contains { ($0 as? CKError)?.code == .zoneNotFound }
    }

    // MARK: - 映射

    static func record(for change: SyncChange, zoneID: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(
            recordType: "SyncChange",
            recordID: CKRecord.ID(recordName: change.changeID, zoneID: zoneID)
        )
        record["entity"] = change.entity as CKRecordValue
        record["entityID"] = change.entityID as CKRecordValue
        record["field"] = change.field as CKRecordValue
        record["value"] = change.valueJSON as CKRecordValue
        record["rev"] = change.rev as CKRecordValue
        record["ms"] = change.ms as CKRecordValue
        record["seq"] = change.seq as CKRecordValue
        record["device"] = change.deviceID as CKRecordValue
        return record
    }

    static func change(from record: CKRecord) -> SyncChange? {
        guard let entity = record["entity"] as? String,
              let entityID = record["entityID"] as? String,
              let field = record["field"] as? String,
              let value = record["value"] as? String,
              let rev = record["rev"] as? String,
              let ms = record["ms"] as? Int64,
              let seq = record["seq"] as? Int64,
              let device = record["device"] as? String
        else { return nil }

        return SyncChange(
            seq: seq,
            entity: entity,
            entityID: entityID,
            field: field,
            valueJSON: value,
            rev: rev,
            deviceID: device,
            ms: ms
        )
    }

    // MARK: - token 编解码

    static func encodeToken(_ token: CKServerChangeToken) -> String? {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token, requiringSecureCoding: true
        ) else { return nil }
        return data.base64EncodedString()
    }

    static func decodeToken(_ raw: String) -> CKServerChangeToken? {
        guard let data = Data(base64Encoded: raw) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKServerChangeToken.self, from: data
        )
    }
}
