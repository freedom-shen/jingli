import Foundation
import GRDB

/// 本地同步元数据、变更日志和 trigger。
///
/// 设计要点：
/// - 业务表结构不变，变更由 SQLite trigger 捕获，避免漏掉 CLI / Agent / 备份导入的写入。
/// - 每条变更只记录一个字段；`rev` 是 HLC（毫秒 + 设备 + 序号），用于字段级 LWW。
/// - 拉取游标用云端 `createdAt`，`rev` 只做冲突排序。
/// - `suppress` 用于两类写入：跨天 rollover（本地派生，不推送）和 apply 远端变更（不回写）。
enum SyncSchema {
    static let deviceIDKey = "device_id"
    static let maxMSKey = "max_ms"
    static let suppressKey = "suppress"

    static func migrate(_ db: Database) throws {
        try createTables(db)
        try insertMetadata(db)
        try createChangeTrigger(db)
        try createTableTriggers(db)
    }

    /// 静默写入：不产生同步变更，适合 rollover 这类本地派生状态。
    static func withSuppressed(_ db: Database, _ body: () throws -> Void) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_meta (key, value) VALUES (?, '1')
            ON CONFLICT(key) DO UPDATE SET value = '1'
            """,
            arguments: [suppressKey]
        )
        defer {
            try? db.execute(
                sql: "DELETE FROM sync_meta WHERE key = ?",
                arguments: [suppressKey]
            )
        }
        try body()
    }

    // MARK: - Schema

    private static func createTables(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE sync_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            CREATE TABLE sync_clock (
                key TEXT PRIMARY KEY,
                value INTEGER NOT NULL
            )
            """)
        try db.execute(sql: """
            CREATE TABLE sync_change (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                entity TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                field TEXT NOT NULL,
                value TEXT NOT NULL,
                ms INTEGER NOT NULL,
                device_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                pushed_at TEXT,
                rev TEXT GENERATED ALWAYS AS (
                    printf('%016llx-%s-%016llx', ms, device_id, seq)
                ) VIRTUAL
            )
            """)
        try db.execute(sql: """
            CREATE INDEX sync_change_pending_idx
            ON sync_change (pushed_at, seq)
            """)
        try db.execute(sql: """
            CREATE INDEX sync_change_entity_idx
            ON sync_change (entity, entity_id)
            """)
        try db.execute(sql: """
            CREATE TABLE sync_field_rev (
                entity TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                field TEXT NOT NULL,
                rev TEXT NOT NULL,
                PRIMARY KEY (entity, entity_id, field)
            )
            """)
        try db.execute(sql: """
            CREATE TABLE sync_tombstone (
                entity TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                rev TEXT NOT NULL,
                PRIMARY KEY (entity, entity_id)
            )
            """)
    }

    private static func insertMetadata(_ db: Database) throws {
        let deviceID = UUID().uuidString.lowercased()
        try db.execute(
            sql: "INSERT OR IGNORE INTO sync_meta (key, value) VALUES (?, ?)",
            arguments: [deviceIDKey, deviceID]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO sync_clock (key, value) VALUES (?, 0)",
            arguments: [maxMSKey]
        )
    }

    // MARK: - Change bookkeeping

    private static func createChangeTrigger(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TRIGGER sync_change_ai
            AFTER INSERT ON sync_change
            BEGIN
                INSERT INTO sync_field_rev (entity, entity_id, field, rev)
                VALUES (NEW.entity, NEW.entity_id, NEW.field, NEW.rev)
                ON CONFLICT(entity, entity_id, field) DO UPDATE
                SET rev = excluded.rev
                WHERE excluded.rev > sync_field_rev.rev;

                INSERT INTO sync_tombstone (entity, entity_id, rev)
                SELECT NEW.entity, NEW.entity_id, NEW.rev
                WHERE NEW.field = '__deleted'
                ON CONFLICT(entity, entity_id) DO UPDATE
                SET rev = excluded.rev
                WHERE excluded.rev > sync_tombstone.rev;

                INSERT INTO sync_clock (key, value) VALUES ('max_ms', NEW.ms)
                ON CONFLICT(key) DO UPDATE
                SET value = MAX(value, excluded.value);
            END
            """)
    }

    // MARK: - Table triggers

    private struct ColumnSpec: Sendable {
        let field: String
        let column: String
        let valueSQL: @Sendable (String) -> String
    }

    private struct TableSpec: Sendable {
        let table: String
        let entity: String
        let idSQL: @Sendable (String) -> String
        let columns: [ColumnSpec]
        let insertPresent: Bool
        let deleteField: String
        let deleteValue: String
    }

    private static let tables: [TableSpec] = [
        TableSpec(
            table: "project",
            entity: "project",
            idSQL: { "\($0).\"id\"" },
            columns: [
                text("name", "name"),
                text("description", "description"),
                text("color", "color"),
                text("created_at", "created_at")
            ],
            insertPresent: false,
            deleteField: "__deleted",
            deleteValue: "true"
        ),
        TableSpec(
            table: "task",
            entity: "task",
            idSQL: { "\($0).\"id\"" },
            columns: [
                text("title", "title"),
                optionalText("project_id", "project_id"),
                text("lane", "lane"),
                optionalText("planned_date", "planned_date"),
                text("note", "note"),
                bool("done", "done"),
                text("created_at", "created_at"),
                optionalText("completed_at", "completed_at"),
                optionalInt("estimate", "estimate")
            ],
            insertPresent: false,
            deleteField: "__deleted",
            deleteValue: "true"
        ),
        TableSpec(
            table: "day_plan",
            entity: "dayPlan",
            idSQL: { "\($0).\"date\"" },
            columns: [
                bool("started", "started"),
                optionalText("started_at", "started_at")
            ],
            insertPresent: false,
            deleteField: "__deleted",
            deleteValue: "true"
        ),
        TableSpec(
            table: "day_plan_task",
            entity: "dayPlanTask",
            idSQL: { "\($0).\"date\" || '|' || \($0).\"task_id\"" },
            columns: [
                text("lane", "lane"),
                text("selected_at", "selected_at")
            ],
            insertPresent: true,
            deleteField: "__present",
            deleteValue: "false"
        ),
        TableSpec(
            table: "focus_session",
            entity: "focusSession",
            idSQL: { "\($0).\"id\"" },
            columns: [
                text("session_date", "session_date"),
                text("started_at", "started_at"),
                optionalText("ended_at", "ended_at"),
                int("duration_sec", "duration_sec"),
                text("status", "status"),
                bool("credited", "credited"),
                bool("focus_mode_on", "focus_mode_on"),
                bool("focus_mode_owned", "focus_mode_owned")
            ],
            insertPresent: false,
            deleteField: "__deleted",
            deleteValue: "true"
        ),
        TableSpec(
            table: "focus_session_task",
            entity: "focusSessionTask",
            idSQL: { "\($0).\"session_id\" || '|' || \($0).\"task_id\"" },
            columns: [
                double("share", "share")
            ],
            insertPresent: true,
            deleteField: "__present",
            deleteValue: "false"
        ),
        TableSpec(
            table: "task_completion",
            entity: "taskCompletion",
            idSQL: { "\($0).\"id\"" },
            columns: [
                text("task_id", "task_id"),
                text("completed_at", "completed_at")
            ],
            insertPresent: false,
            deleteField: "__deleted",
            deleteValue: "true"
        )
    ]

    private static func createTableTriggers(_ db: Database) throws {
        for spec in tables {
            try db.execute(sql: insertTrigger(spec))
            try db.execute(sql: updateTrigger(spec))
            try db.execute(sql: deleteTrigger(spec))
        }
    }

    private static func insertTrigger(_ spec: TableSpec) -> String {
        var statements: [String] = []
        if spec.insertPresent {
            statements.append(
                changeInsert(
                    entity: spec.entity,
                    entityID: spec.idSQL("NEW"),
                    field: "__present",
                    value: "'true'",
                    condition: "1"
                )
            )
        }
        for column in spec.columns {
            statements.append(
                changeInsert(
                    entity: spec.entity,
                    entityID: spec.idSQL("NEW"),
                    field: column.field,
                    value: column.valueSQL("NEW"),
                    condition: "1"
                )
            )
        }
        return """
            CREATE TRIGGER sync_\(spec.table)_ai
            AFTER INSERT ON \(spec.table)
            BEGIN
            \(statements.joined(separator: "\n"))
            END
            """
    }

    private static func updateTrigger(_ spec: TableSpec) -> String {
        let statements = spec.columns.map { column in
            changeInsert(
                entity: spec.entity,
                entityID: spec.idSQL("NEW"),
                field: column.field,
                value: column.valueSQL("NEW"),
                condition: "NEW.\"\(column.column)\" IS NOT OLD.\"\(column.column)\""
            )
        }
        return """
            CREATE TRIGGER sync_\(spec.table)_au
            AFTER UPDATE ON \(spec.table)
            BEGIN
            \(statements.joined(separator: "\n"))
            END
            """
    }

    private static func deleteTrigger(_ spec: TableSpec) -> String {
        let statement = changeInsert(
            entity: spec.entity,
            entityID: spec.idSQL("OLD"),
            field: spec.deleteField,
            value: "'\(spec.deleteValue)'",
            condition: "1"
        )
        return """
            CREATE TRIGGER sync_\(spec.table)_ad
            AFTER DELETE ON \(spec.table)
            BEGIN
            \(statement)
            END
            """
    }

    private static func changeInsert(
        entity: String,
        entityID: String,
        field: String,
        value: String,
        condition: String
    ) -> String {
        """
        INSERT INTO sync_change
            (entity, entity_id, field, value, ms, device_id, created_at)
        SELECT \(sqlString(entity)), \(entityID), \(sqlString(field)), \(value),
               \(msExpression),
               (SELECT value FROM sync_meta WHERE key = 'device_id'),
               strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
        WHERE \(condition)
          AND NOT EXISTS (
              SELECT 1 FROM sync_meta
              WHERE key = 'suppress' AND value = '1'
          );
        """
    }

    private static let msExpression = """
        MAX(
            CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER),
            COALESCE((SELECT value FROM sync_clock WHERE key = 'max_ms'), 0) + 1
        )
        """

    // MARK: - Column helpers

    private static func text(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            "json_quote(\(prefix).\"\(column)\")"
        }
    }

    private static func optionalText(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            """
            CASE WHEN \(prefix)."\(column)" IS NULL THEN 'null'
                 ELSE json_quote(\(prefix)."\(column)") END
            """
        }
    }

    private static func bool(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            "CASE WHEN \(prefix).\"\(column)\" THEN 'true' ELSE 'false' END"
        }
    }

    private static func int(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            "CAST(\(prefix).\"\(column)\" AS TEXT)"
        }
    }

    private static func optionalInt(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            """
            CASE WHEN \(prefix)."\(column)" IS NULL THEN 'null'
                 ELSE CAST(\(prefix)."\(column)" AS TEXT) END
            """
        }
    }

    private static func double(_ field: String, _ column: String) -> ColumnSpec {
        ColumnSpec(field: field, column: column) { prefix in
            "CAST(\(prefix).\"\(column)\" AS TEXT)"
        }
    }

    private static func sqlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
