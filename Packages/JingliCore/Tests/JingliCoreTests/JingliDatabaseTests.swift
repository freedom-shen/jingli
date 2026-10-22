import XCTest
import GRDB
@testable import JingliCore

final class JingliDatabaseTests: XCTestCase {
    func testSchemaIsCreated() throws {
        let db = try JingliDatabase.inMemory()
        let tables = try db.queue.read { database in
            try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }
        XCTAssertTrue(tables.contains("project"))
        XCTAssertTrue(tables.contains("task"))
        XCTAssertTrue(tables.contains("day_plan"))
        XCTAssertTrue(tables.contains("focus_session"))
        XCTAssertTrue(tables.contains("focus_session_task"))
        XCTAssertTrue(tables.contains("agent_event"))
        XCTAssertTrue(tables.contains("setting"))
    }

    func testRolloverKeepsTodayAndClearsYesterday() throws {
        let db = try JingliDatabase.inMemory()
        try seed(db)

        try db.rollover(to: "2026-10-22")

        try db.queue.read { database in
            let t1Date = try String.fetchOne(
                database,
                sql: "SELECT planned_date FROM task WHERE id = ?",
                arguments: ["t1"]
            )
            XCTAssertNil(t1Date, "未完成任务应回到未安排")

            let t2 = try Row.fetchOne(
                database,
                sql: "SELECT done, planned_date FROM task WHERE id = ?",
                arguments: ["t2"]
            )
            XCTAssertEqual(t2?["done"] as Bool?, true, "已完成任务保持完成状态")
            XCTAssertEqual(t2?["planned_date"] as String?, "2026-10-21")

            let t3Date = try String.fetchOne(
                database,
                sql: "SELECT planned_date FROM task WHERE id = ?",
                arguments: ["t3"]
            )
            XCTAssertEqual(t3Date, "2026-10-22")

            let sessions = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM focus_session")
            XCTAssertEqual(sessions, 1, "只保留今天的番茄记录")

            let oldSessionTasks = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM focus_session_task WHERE session_id = ?",
                arguments: ["s-old"]
            )
            XCTAssertEqual(oldSessionTasks, 0, "级联删除旧 session 的任务关联")

            let oldPlans = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM day_plan WHERE date < ?",
                arguments: ["2026-10-22"]
            )
            XCTAssertEqual(oldPlans, 0)
        }
    }

    func testPurgeSessionsDoesNotTouchTasks() throws {
        let db = try JingliDatabase.inMemory()
        try seed(db)

        try db.purgeSessions(before: "2026-10-22")

        try db.queue.read { database in
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM focus_session"),
                1
            )
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM task"),
                3
            )
        }
    }

    func testDeletingProjectKeepsTasksUncategorized() throws {
        let db = try JingliDatabase.inMemory()
        try seed(db)

        try db.queue.write { database in
            try database.execute(sql: "DELETE FROM project WHERE id = ?", arguments: ["p1"])
        }

        try db.queue.read { database in
            let projectID = try String.fetchOne(
                database,
                sql: "SELECT project_id FROM task WHERE id = ?",
                arguments: ["t1"]
            )
            XCTAssertNil(projectID)
            XCTAssertEqual(
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM task"),
                3
            )
        }
    }

    private func seed(_ db: JingliDatabase) throws {
        try db.queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO project (id, name, description, color, created_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: ["p1", "工作", "", "sage", "2026-10-21T09:00:00Z", 0]
            )

            try database.execute(
                sql: """
                INSERT INTO task
                (id, title, project_id, lane, planned_date, note, done, created_at, completed_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["t1", "未完成", "p1", "main", "2026-10-21", "", false, "2026-10-21T09:00:00Z", nil, 0]
            )
            try database.execute(
                sql: """
                INSERT INTO task
                (id, title, project_id, lane, planned_date, note, done, created_at, completed_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["t2", "已完成", "p1", "main", "2026-10-21", "", true, "2026-10-21T09:00:00Z", "2026-10-21T10:00:00Z", 1]
            )
            try database.execute(
                sql: """
                INSERT INTO task
                (id, title, project_id, lane, planned_date, note, done, created_at, completed_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["t3", "今天", "p1", "temporary", "2026-10-22", "", false, "2026-10-22T09:00:00Z", nil, 2]
            )

            try database.execute(
                sql: "INSERT INTO day_plan (date, started, started_at) VALUES (?, ?, ?)",
                arguments: ["2026-10-21", true, "2026-10-21T09:00:00Z"]
            )
            try database.execute(
                sql: "INSERT INTO day_plan (date, started, started_at) VALUES (?, ?, ?)",
                arguments: ["2026-10-22", true, "2026-10-22T09:00:00Z"]
            )
            try database.execute(
                sql: "INSERT INTO day_plan_task (date, task_id, lane, selected_at) VALUES (?, ?, ?, ?)",
                arguments: ["2026-10-21", "t1", "main", "2026-10-21T09:00:00Z"]
            )

            for (id, date) in [("s-old", "2026-10-21"), ("s-today", "2026-10-22")] {
                try database.execute(
                    sql: """
                    INSERT INTO focus_session
                    (id, session_date, started_at, ended_at, duration_sec, status, credited, focus_mode_on, focus_mode_owned)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [id, date, "\(date)T09:00:00Z", "\(date)T09:25:00Z", 1500, "completed", true, true, true]
                )
                try database.execute(
                    sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES (?, ?, ?)",
                    arguments: [id, "t1", 1.0]
                )
            }
        }
    }
}
