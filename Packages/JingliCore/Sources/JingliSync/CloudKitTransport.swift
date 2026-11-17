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
        try await ensureZone()

        var accepted: [String] = []
        for start in stride(from: 0, to: changes.count, by: batchSize) {
            let batch = Array(changes[start..<min(start + batchSize, changes.count)])
            let records = batch.map { Self.record(for: $0, zoneID: zoneID) }
            let (saveResults, _) = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
            if saveResults.values.allSatisfy({ if case .failure = $0 { return true } else { return false } }),
               saveResults.count == batch.count {
                // 整批都被拒：多半是 zone 刚建好还没就绪，等一下重试一次
                try? await _Concurrency.Task.sleep(nanoseconds: 1_200_000_000)
                let retry = try await database.modifyRecords(
                    saving: records,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
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
        try await ensureZone()

        let box = CollectBox()
        let token = cursor.flatMap(Self.decodeToken)
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: token,
            resultsLimit: nil,
            desiredKeys: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.recordWasChangedBlock = { _, result in
                if case let .success(record) = result { box.append(record) }
            }
            operation.recordWithIDWasDeletedBlock = { _, _ in
                // 删除靠业务字段里的 __deleted（tombstone），忽略物理删除。
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case let .success(response) = result {
                    let (serverToken, _, _) = response
                    box.setToken(serverToken)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        // token 过期：清掉游标从头拉，交给上层重新保存
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            database.add(operation)
        }

        let changes = box.records().compactMap(Self.change(from:))
        // 按 seq 排序，尽量还原写入顺序；真正的顺序判断仍在 SyncStore 里按 rev 做。
        return (changes.sorted { $0.seq < $1.seq }, box.token().flatMap(Self.encodeToken))
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

/// CloudKit 的回调在多个线程上跑；用锁保护收集过程，避免数据竞争。
private final class CollectBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CKRecord] = []
    private var serverToken: CKServerChangeToken?

    func append(_ record: CKRecord) {
        lock.lock(); defer { lock.unlock() }
        items.append(record)
    }

    func setToken(_ token: CKServerChangeToken?) {
        lock.lock(); defer { lock.unlock() }
        serverToken = token
    }

    func records() -> [CKRecord] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    func token() -> CKServerChangeToken? {
        lock.lock(); defer { lock.unlock() }
        return serverToken
    }
}
