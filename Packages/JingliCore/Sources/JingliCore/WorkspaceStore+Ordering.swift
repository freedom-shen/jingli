import Foundation
import GRDB

/// 手动排序：今日（主线 / 临时，按天隔离）和项目任务列表的拖动排序都存这里。
/// scope 约定：`today:<yyyy-MM-dd>:main`、`today:<yyyy-MM-dd>:temporary`、`project:<id>`。
public extension WorkspaceStore {
    /// scope 内任务的展示顺序：有显式排序的按 position 排，其余按 fallback 原顺序追加在后面。
    func orderedTasks(scope: String, fallback: [Task]) throws -> [Task] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT task_id, position FROM task_order WHERE scope = ?",
                arguments: [scope]
            )
            var positionByID: [String: Int] = [:]
            for row in rows {
                positionByID[row["task_id"]] = row["position"]
            }
            let explicit = fallback
                .filter { positionByID[$0.id] != nil }
                .sorted { lhs, rhs in
                    let lp = positionByID[lhs.id]!
                    let rp = positionByID[rhs.id]!
                    if lp != rp { return lp < rp }
                    return lhs.createdAt > rhs.createdAt
                }
            let rest = fallback.filter { positionByID[$0.id] == nil }
            return explicit + rest
        }
    }

    /// 测试 / 快照夹具用：直接钉任务的 created_at，绕过业务写入的默认时间。
    func setTaskCreatedAt(id: String, createdAt: String) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET created_at = ? WHERE id = ?",
                arguments: [createdAt, id]
            )
        }
    }

    /// 保存 scope 的顺序（orderedIDs 全量重写）。今天 scope 写入时顺带清掉其它日期的排序，避免堆积。
    func saveTaskOrder(scope: String, orderedIDs: [String]) throws {
        try database.queue.write { db in
            if scope.hasPrefix("today:") {
                try db.execute(
                    sql: "DELETE FROM task_order WHERE scope LIKE 'today:%' AND scope != ?",
                    arguments: [scope]
                )
            }
            try db.execute(
                sql: "DELETE FROM task_order WHERE scope = ?",
                arguments: [scope]
            )
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO task_order (scope, task_id, position)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [scope, id, index]
                )
            }
        }
    }
}
