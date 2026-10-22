import Foundation
import GRDB

/// 只管今天的 SQLite 存储。
///
/// 约定：
/// - `focus_session` 只保留 `session_date == today` 的记录，跨天删除。
/// - 未完成任务跨天回到未安排；已完成任务保留完成状态。
/// - 旧番茄历史不导入、不保留。
public final class JingliDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue

    public init(_ queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    public static func inMemory() throws -> JingliDatabase {
        try JingliDatabase(try DatabaseQueue())
    }

    public static func onDisk(at url: URL) throws -> JingliDatabase {
        try JingliDatabase(try DatabaseQueue(path: url.path))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_today") { db in
            try db.create(table: "project") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("color", .text).notNull().defaults(to: "sage")
                t.column("created_at", .text).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "task") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("project_id", .text)
                    .references("project", onDelete: .setNull)
                t.column("lane", .text).notNull().defaults(to: "main")
                t.column("planned_date", .text)
                t.column("note", .text).notNull().defaults(to: "")
                t.column("done", .boolean).notNull().defaults(to: false)
                t.column("created_at", .text).notNull()
                t.column("completed_at", .text)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "task_project_idx", on: "task", columns: ["project_id"])
            try db.create(index: "task_date_idx", on: "task", columns: ["planned_date"])

            try db.create(table: "day_plan") { t in
                t.column("date", .text).primaryKey()
                t.column("started", .boolean).notNull().defaults(to: false)
                t.column("started_at", .text)
            }

            try db.create(table: "day_plan_task") { t in
                t.column("date", .text).notNull()
                t.column("task_id", .text).notNull()
                    .references("task", onDelete: .cascade)
                t.column("lane", .text).notNull().defaults(to: "main")
                t.column("selected_at", .text).notNull()
                t.primaryKey(["date", "task_id"])
            }

            try db.create(table: "focus_session") { t in
                t.column("id", .text).primaryKey()
                t.column("session_date", .text).notNull()
                t.column("started_at", .text).notNull()
                t.column("ended_at", .text)
                t.column("duration_sec", .integer).notNull()
                t.column("status", .text).notNull()
                t.column("credited", .boolean).notNull().defaults(to: false)
                t.column("focus_mode_on", .boolean).notNull().defaults(to: false)
                t.column("focus_mode_owned", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "focus_session_date_idx", on: "focus_session", columns: ["session_date"])

            try db.create(table: "focus_session_task") { t in
                t.column("session_id", .text).notNull()
                    .references("focus_session", onDelete: .cascade)
                t.column("task_id", .text).notNull()
                    .references("task", onDelete: .cascade)
                t.column("share", .double).notNull()
                t.primaryKey(["session_id", "task_id"])
            }

            try db.create(table: "agent_event") { t in
                t.column("id", .text).primaryKey()
                t.column("at", .text).notNull()
                t.column("actor", .text).notNull()
                t.column("action", .text).notNull()
                t.column("payload", .text).notNull().defaults(to: "{}")
                t.column("undo", .text)
            }

            try db.create(table: "setting") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }
        return migrator
    }

    /// 跨天：未完成任务回未安排；今日以前的番茄记录、旧日计划全部删除。
    public func rollover(to today: String) throws {
        try queue.write { db in
            try db.execute(
                sql: """
                UPDATE task
                SET planned_date = NULL
                WHERE done = 0 AND planned_date IS NOT NULL AND planned_date < ?
                """,
                arguments: [today]
            )
            try db.execute(
                sql: "DELETE FROM focus_session WHERE session_date < ?",
                arguments: [today]
            )
            try db.execute(
                sql: "DELETE FROM day_plan WHERE date < ?",
                arguments: [today]
            )
            try db.execute(
                sql: "DELETE FROM day_plan_task WHERE date < ?",
                arguments: [today]
            )
        }
    }

    /// 只清番茄记录，不动任务。
    public func purgeSessions(before today: String) throws {
        try queue.write { db in
            try db.execute(
                sql: "DELETE FROM focus_session WHERE session_date < ?",
                arguments: [today]
            )
        }
    }
}
