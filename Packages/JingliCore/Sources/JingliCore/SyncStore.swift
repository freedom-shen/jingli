import Foundation
import GRDB

/// 一条可同步的字段变更。
///
/// `rev` 形如 `000001a1a77ebea0-<device>-0000000000000001`，前 16 位是毫秒，
/// 中间是设备 ID，最后是本地序号；按字符串比较即可得到 HLC 顺序。
public struct SyncChange: Codable, Sendable, Equatable {
    public let seq: Int64
    public let entity: String
    public let entityID: String
    public let field: String
    public let valueJSON: String
    public let rev: String
    public let deviceID: String
    public let ms: Int64

    public var changeID: String { "\(deviceID):\(seq)" }

    init(row: Row) {
        self.seq = row["seq"]
        self.entity = row["entity"]
        self.entityID = row["entity_id"]
        self.field = row["field"]
        self.valueJSON = row["value"]
        self.rev = row["rev"]
        self.deviceID = row["device_id"]
        self.ms = row["ms"]
    }
}

/// 本地变更日志 / 远端变更归并。
///
/// 这里不负责网络，只负责：
/// - 读取待推送的变更；
/// - 标记已推送；
/// - 把远端变更按字段级 LWW 应用到本地 SQLite。
public final class SyncStore: @unchecked Sendable {
    private let database: JingliDatabase

    public init(database: JingliDatabase) {
        self.database = database
    }

    // MARK: - Local changes

    public func pendingChanges(limit: Int = 500) throws -> [SyncChange] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT seq, entity, entity_id, field, value, rev, device_id, ms
                FROM sync_change
                WHERE pushed_at IS NULL
                ORDER BY seq
                LIMIT ?
                """,
                arguments: [max(1, min(limit, 1000))]
            ).map(SyncChange.init(row:))
        }
    }

    public func allChanges(after seq: Int64 = 0) throws -> [SyncChange] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT seq, entity, entity_id, field, value, rev, device_id, ms
                FROM sync_change
                WHERE seq > ?
                ORDER BY seq
                """,
                arguments: [seq]
            ).map(SyncChange.init(row:))
        }
    }

    public func markPushed(_ changes: [SyncChange], at date: Date = Date()) throws {
        guard !changes.isEmpty else { return }
        let seqs = changes.map(\.seq)
        let placeholders = Array(repeating: "?", count: seqs.count).joined(separator: ",")
        var arguments: [(any DatabaseValueConvertible)?] = [Self.timestamp(date)]
        for seq in seqs { arguments.append(seq) }
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE sync_change SET pushed_at = ? WHERE seq IN (\(placeholders))",
                arguments: StatementArguments(arguments)
            )
        }
    }

    public func pendingCount() throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sync_change WHERE pushed_at IS NULL"
            ) ?? 0
        }
    }

    public func lastSeq() throws -> Int64 {
        try database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(seq), 0) FROM sync_change") ?? 0
        }
    }

    public func deviceID() throws -> String {
        try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_meta WHERE key = 'device_id'"
            ) ?? ""
        }
    }

    public func fieldRev(
        entity: String,
        entityID: String,
        field: String
    ) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT rev FROM sync_field_rev
                WHERE entity = ? AND entity_id = ? AND field = ?
                """,
                arguments: [entity, entityID, field]
            )
        }
    }

    public func tombstoneRev(entity: String, entityID: String) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT rev FROM sync_tombstone WHERE entity = ? AND entity_id = ?",
                arguments: [entity, entityID]
            )
        }
    }

    // MARK: - Applying remote changes

    public func apply(_ changes: [SyncChange]) throws {
        guard !changes.isEmpty else { return }
        let sorted = changes.sorted { lhs, rhs in
            let lp = Self.schemasByEntity[lhs.entity]?.priority ?? Int.max
            let rp = Self.schemasByEntity[rhs.entity]?.priority ?? Int.max
            if lp != rp { return lp < rp }
            if lhs.rev != rhs.rev { return lhs.rev < rhs.rev }
            return lhs.seq < rhs.seq
        }

        try database.queue.write { db in
            try SyncSchema.withSuppressed(db) {
                for change in sorted {
                    try Self.advanceClock(db, ms: change.ms)
                    do {
                        try applyOne(db, change)
                    } catch let error as DatabaseError
                        where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
                        // 对端可能还没同步到被引用的 task/session；跳过，等下一轮。
                        continue
                    }
                }
            }
        }
    }

    private func applyOne(_ db: Database, _ change: SyncChange) throws {
        guard let schema = Self.schemasByEntity[change.entity] else { return }

        switch change.field {
        case "__deleted":
            try applyDelete(db, schema: schema, change: change)
        case "__present":
            try applyPresence(db, schema: schema, change: change)
        default:
            guard let column = schema.columns.first(where: { $0.field == change.field }) else {
                return
            }
            if schema.deleteMode == .tombstone,
               try tombstoneRev(db, entity: schema.entity, entityID: change.entityID) != nil {
                return
            }
            let barrier = try barrierRev(
                db,
                schema: schema,
                entityID: change.entityID,
                field: change.field
            )
            guard change.rev > barrier else { return }

            let value = try Self.parseValue(change.valueJSON)
            // 只管理今天：远端“过去的 planned_date”是离线端迟到的旧值，直接丢弃。
            // rollover 本身不产生变更，避免离线机器清掉另一台今天刚排好的计划。
            if schema.entity == "task", change.field == "planned_date",
               let date = value as? String, date < DayKey.make() {
                return
            }
            try ensureRow(
                db,
                schema: schema,
                entityID: change.entityID,
                change: change,
                value: value
            )
            try db.execute(
                sql: """
                UPDATE \(schema.table) SET "\(column.column)" = ?
                WHERE \(Self.whereSQL(schema))
                """,
                arguments: StatementArguments(
                    [Self.typedValue(value, kind: column.kind)]
                        + Self.keyArguments(schema, entityID: change.entityID)
                )
            )
            try setFieldRev(
                db,
                entity: schema.entity,
                entityID: change.entityID,
                field: change.field,
                rev: change.rev
            )
        }
    }

    private func applyDelete(
        _ db: Database,
        schema: ApplySchema,
        change: SyncChange
    ) throws {
        let current = try fieldRev(
            db,
            entity: schema.entity,
            entityID: change.entityID,
            field: "__deleted"
        ) ?? ""
        guard change.rev > current else { return }

        if schema.entity == "project" {
            let taskIDs = try String.fetchAll(
                db,
                sql: "SELECT id FROM task WHERE project_id = ?",
                arguments: [change.entityID]
            )
            try db.execute(
                sql: "UPDATE task SET project_id = NULL WHERE project_id = ?",
                arguments: [change.entityID]
            )
            for taskID in taskIDs {
                try setFieldRev(
                    db,
                    entity: "task",
                    entityID: taskID,
                    field: "project_id",
                    rev: change.rev
                )
            }
        }

        try db.execute(
            sql: "DELETE FROM \(schema.table) WHERE \(Self.whereSQL(schema))",
            arguments: StatementArguments(
                Self.keyArguments(schema, entityID: change.entityID)
            )
        )
        try setFieldRev(
            db,
            entity: schema.entity,
            entityID: change.entityID,
            field: "__deleted",
            rev: change.rev
        )
        if schema.deleteMode == .tombstone {
            try db.execute(
                sql: """
                INSERT INTO sync_tombstone (entity, entity_id, rev)
                VALUES (?, ?, ?)
                ON CONFLICT(entity, entity_id) DO UPDATE
                SET rev = excluded.rev
                WHERE excluded.rev > sync_tombstone.rev
                """,
                arguments: [schema.entity, change.entityID, change.rev]
            )
        }
    }

    private func applyPresence(
        _ db: Database,
        schema: ApplySchema,
        change: SyncChange
    ) throws {
        let current = try fieldRev(
            db,
            entity: schema.entity,
            entityID: change.entityID,
            field: "__present"
        ) ?? ""
        guard change.rev > current else { return }

        let value = try Self.parseValue(change.valueJSON)
        if Self.boolValue(value) {
            try ensureRow(
                db,
                schema: schema,
                entityID: change.entityID,
                change: change,
                value: nil
            )
        } else {
            try db.execute(
                sql: "DELETE FROM \(schema.table) WHERE \(Self.whereSQL(schema))",
                arguments: StatementArguments(
                    Self.keyArguments(schema, entityID: change.entityID)
                )
            )
        }
        try setFieldRev(
            db,
            entity: schema.entity,
            entityID: change.entityID,
            field: "__present",
            rev: change.rev
        )
    }

    /// 首次收到某个实体的字段时，用默认值把行建出来；后续字段再逐列更新。
    private func ensureRow(
        _ db: Database,
        schema: ApplySchema,
        entityID: String,
        change: SyncChange,
        value: Any?
    ) throws {
        let keys = schema.keyValues(for: entityID)
        guard keys.count == schema.keyColumns.count else {
            throw SyncApplyError.invalidEntityID(entityID)
        }
        let exists = try Bool.fetchOne(
            db,
            sql: """
            SELECT EXISTS(
                SELECT 1 FROM \(schema.table) WHERE \(Self.whereSQL(schema))
            )
            """,
            arguments: StatementArguments(Self.keyArguments(schema, entityID: entityID))
        ) ?? false
        guard !exists else { return }

        var values: [String: (any DatabaseValueConvertible)?] = [:]
        for column in schema.insertColumns {
            if let literal = schema.defaults[column] {
                values[column] = literal.databaseValue
            } else if schema.nowColumns.contains(column) {
                values[column] = Self.timestamp()
            } else if schema.todayColumns.contains(column) {
                values[column] = DayKey.make()
            } else {
                values[column] = nil
            }
        }
        for (key, value) in keys {
            values[key] = value
        }
        if let column = schema.columns.first(where: { $0.field == change.field }) {
            values[column.column] = Self.typedValue(value, kind: column.kind)
        }

        let columns = schema.insertColumns
        let columnSQL = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: columns.count)
            .joined(separator: ", ")
        try db.execute(
            sql: "INSERT INTO \(schema.table) (\(columnSQL)) VALUES (\(placeholders))",
            arguments: StatementArguments(columns.map { values[$0] ?? nil })
        )
    }

    // MARK: - Rev helpers

    private func barrierRev(
        _ db: Database,
        schema: ApplySchema,
        entityID: String,
        field: String
    ) throws -> String {
        var revs: [String] = []
        if let rev = try fieldRev(
            db,
            entity: schema.entity,
            entityID: entityID,
            field: field
        ) {
            revs.append(rev)
        }
        switch schema.deleteMode {
        case .tombstone:
            break
        case .row:
            if let rev = try fieldRev(
                db,
                entity: schema.entity,
                entityID: entityID,
                field: "__deleted"
            ) {
                revs.append(rev)
            }
        case .presence:
            if let rev = try fieldRev(
                db,
                entity: schema.entity,
                entityID: entityID,
                field: "__present"
            ) {
                revs.append(rev)
            }
        }
        return revs.max() ?? ""
    }

    private func fieldRev(
        _ db: Database,
        entity: String,
        entityID: String,
        field: String
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: """
            SELECT rev FROM sync_field_rev
            WHERE entity = ? AND entity_id = ? AND field = ?
            """,
            arguments: [entity, entityID, field]
        )
    }

    private func tombstoneRev(
        _ db: Database,
        entity: String,
        entityID: String
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT rev FROM sync_tombstone WHERE entity = ? AND entity_id = ?",
            arguments: [entity, entityID]
        )
    }

    private func setFieldRev(
        _ db: Database,
        entity: String,
        entityID: String,
        field: String,
        rev: String
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_field_rev (entity, entity_id, field, rev)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(entity, entity_id, field) DO UPDATE
            SET rev = excluded.rev
            WHERE excluded.rev > sync_field_rev.rev
            """,
            arguments: [entity, entityID, field, rev]
        )
    }

    private static func advanceClock(_ db: Database, ms: Int64) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_clock (key, value) VALUES ('max_ms', ?)
            ON CONFLICT(key) DO UPDATE SET value = MAX(value, excluded.value)
            """,
            arguments: [ms]
        )
    }

    // MARK: - JSON

    private static func parseValue(_ text: String) throws -> Any? {
        let data = Data(text.utf8)
        let value = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
        return value is NSNull ? nil : value
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private static func typedValue(
        _ value: Any?,
        kind: ApplyColumn.Kind
    ) -> (any DatabaseValueConvertible)? {
        guard let value else { return nil }
        switch kind {
        case .text, .optionalText:
            return value as? String
        case .bool:
            return boolValue(value)
        case .int, .optionalInt:
            if let number = value as? NSNumber { return number.intValue }
            return value as? Int
        case .double:
            if let number = value as? NSNumber { return number.doubleValue }
            return value as? Double
        }
    }

    private static func timestamp(_ date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    // MARK: - Entity schemas

    private struct ApplyColumn: Sendable {
        enum Kind: Sendable {
            case text
            case optionalText
            case bool
            case int
            case optionalInt
            case double
        }

        let field: String
        let column: String
        let kind: Kind
    }

    private enum DefaultLiteral: Sendable {
        case text(String)
        case int(Int)
        case double(Double)
        case bool(Bool)

        var databaseValue: any DatabaseValueConvertible {
            switch self {
            case let .text(value): return value
            case let .int(value): return value
            case let .double(value): return value
            case let .bool(value): return value
            }
        }
    }

    private struct ApplySchema: Sendable {
        enum DeleteMode: Sendable {
            /// task / project 等：删除是终态，旧字段变更不能复活。
            case tombstone
            /// day_plan 等：删除后，更高 rev 的字段可以重新建行。
            case row
            /// day_plan_task / focus_session_task：用 __present 表达成员是否存在。
            case presence
        }

        let entity: String
        let table: String
        let keyColumns: [String]
        let columns: [ApplyColumn]
        let insertColumns: [String]
        let defaults: [String: DefaultLiteral]
        let nowColumns: Set<String>
        let todayColumns: Set<String>
        let deleteMode: DeleteMode
        let priority: Int

        func keyValues(for entityID: String) -> [String: String] {
            switch keyColumns.count {
            case 1:
                return [keyColumns[0]: entityID]
            default:
                let parts = entityID.split(
                    separator: "|",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                ).map(String.init)
                guard parts.count == keyColumns.count else { return [:] }
                return Dictionary(uniqueKeysWithValues: zip(keyColumns, parts))
            }
        }
    }

    private static func col(
        _ field: String,
        _ kind: ApplyColumn.Kind,
        _ column: String? = nil
    ) -> ApplyColumn {
        ApplyColumn(field: field, column: column ?? field, kind: kind)
    }

    private static let schemas: [ApplySchema] = [
        ApplySchema(
            entity: "project",
            table: "project",
            keyColumns: ["id"],
            columns: [
                col("name", .text),
                col("description", .text),
                col("color", .text),
                col("created_at", .text)
            ],
            insertColumns: ["id", "name", "description", "color", "created_at", "sort_order"],
            defaults: [
                "name": .text(""),
                "description": .text(""),
                "color": .text("sage"),
                "sort_order": .int(0)
            ],
            nowColumns: ["created_at"],
            todayColumns: [],
            deleteMode: .tombstone,
            priority: 0
        ),
        ApplySchema(
            entity: "task",
            table: "task",
            keyColumns: ["id"],
            columns: [
                col("title", .text),
                col("project_id", .optionalText),
                col("lane", .text),
                col("planned_date", .optionalText),
                col("note", .text),
                col("done", .bool),
                col("created_at", .text),
                col("completed_at", .optionalText),
                col("estimate", .optionalInt)
            ],
            insertColumns: [
                "id", "title", "project_id", "lane", "planned_date", "note",
                "done", "created_at", "completed_at", "sort_order", "estimate"
            ],
            defaults: [
                "title": .text(""),
                "lane": .text("main"),
                "note": .text(""),
                "done": .bool(false),
                "sort_order": .int(0)
            ],
            nowColumns: ["created_at"],
            todayColumns: [],
            deleteMode: .tombstone,
            priority: 1
        ),
        ApplySchema(
            entity: "dayPlan",
            table: "day_plan",
            keyColumns: ["date"],
            columns: [
                col("started", .bool),
                col("started_at", .optionalText)
            ],
            insertColumns: ["date", "started", "started_at"],
            defaults: ["started": .bool(false)],
            nowColumns: [],
            todayColumns: [],
            deleteMode: .row,
            priority: 2
        ),
        ApplySchema(
            entity: "dayPlanTask",
            table: "day_plan_task",
            keyColumns: ["date", "task_id"],
            columns: [
                col("lane", .text),
                col("selected_at", .text)
            ],
            insertColumns: ["date", "task_id", "lane", "selected_at"],
            defaults: ["lane": .text("main")],
            nowColumns: ["selected_at"],
            todayColumns: [],
            deleteMode: .presence,
            priority: 3
        ),
        ApplySchema(
            entity: "focusSession",
            table: "focus_session",
            keyColumns: ["id"],
            columns: [
                col("session_date", .text),
                col("started_at", .text),
                col("ended_at", .optionalText),
                col("duration_sec", .int),
                col("status", .text),
                col("credited", .bool),
                col("focus_mode_on", .bool),
                col("focus_mode_owned", .bool)
            ],
            insertColumns: [
                "id", "session_date", "started_at", "ended_at", "duration_sec",
                "status", "credited", "focus_mode_on", "focus_mode_owned"
            ],
            defaults: [
                "duration_sec": .int(0),
                "status": .text("completed"),
                "credited": .bool(false),
                "focus_mode_on": .bool(false),
                "focus_mode_owned": .bool(false)
            ],
            nowColumns: ["started_at"],
            todayColumns: ["session_date"],
            deleteMode: .tombstone,
            priority: 4
        ),
        ApplySchema(
            entity: "focusSessionTask",
            table: "focus_session_task",
            keyColumns: ["session_id", "task_id"],
            columns: [
                col("share", .double)
            ],
            insertColumns: ["session_id", "task_id", "share"],
            defaults: ["share": .double(0)],
            nowColumns: [],
            todayColumns: [],
            deleteMode: .presence,
            priority: 5
        ),
        ApplySchema(
            entity: "taskCompletion",
            table: "task_completion",
            keyColumns: ["id"],
            columns: [
                col("task_id", .text),
                col("completed_at", .text)
            ],
            insertColumns: ["id", "task_id", "completed_at"],
            defaults: [:],
            nowColumns: ["completed_at"],
            todayColumns: [],
            deleteMode: .tombstone,
            priority: 6
        )
    ]

    private static let schemasByEntity: [String: ApplySchema] = Dictionary(
        uniqueKeysWithValues: schemas.map { ($0.entity, $0) }
    )

    private static func whereSQL(_ schema: ApplySchema) -> String {
        schema.keyColumns.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
    }

    private static func keyArguments(
        _ schema: ApplySchema,
        entityID: String
    ) -> [(any DatabaseValueConvertible)?] {
        let keys = schema.keyValues(for: entityID)
        return schema.keyColumns.map { keys[$0] ?? nil }
    }
}

public enum SyncApplyError: Error, LocalizedError {
    case invalidEntityID(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidEntityID(value):
            return "同步记录的主键格式不正确：\(value)"
        }
    }
}
