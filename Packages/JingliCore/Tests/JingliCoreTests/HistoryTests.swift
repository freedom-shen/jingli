import XCTest
@testable import JingliCore

final class HistoryTests: XCTestCase {
    func testHistoryAggregatesDaysNewestFirst() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")

        try database.queue.write { db in
            for (id, title) in [("t1", "任务一"), ("t2", "任务二"), ("t3", "任务三")] {
                try db.execute(
                    sql: """
                    INSERT INTO task
                    (id, title, project_id, lane, note, done, created_at, completed_at, sort_order)
                    VALUES (?, ?, ?, 'main', '', 1, '2026-10-20T09:00:00Z', NULL, 0)
                    """,
                    arguments: [id, title, project.id]
                )
            }

            try db.execute(
                sql: """
                INSERT INTO task_completion (id, task_id, completed_at)
                VALUES ('c1', 't1', '2026-10-21T02:00:00Z')
                """
            )
            try db.execute(
                sql: """
                INSERT INTO task_completion (id, task_id, completed_at)
                VALUES ('c2', 't2', '2026-10-22T03:00:00Z')
                """
            )

            try db.execute(
                sql: """
                INSERT INTO focus_session
                (id, session_date, started_at, duration_sec, status, credited)
                VALUES ('s1', '2026-10-21', '2026-10-21T01:00:00Z', 1500, 'completed', 1)
                """
            )
            try db.execute(
                sql: """
                INSERT INTO focus_session
                (id, session_date, started_at, duration_sec, status, credited)
                VALUES ('s2', '2026-10-22', '2026-10-22T02:00:00Z', 1800, 'completed', 1)
                """
            )
            try db.execute(
                sql: """
                INSERT INTO focus_session
                (id, session_date, started_at, duration_sec, status, credited)
                VALUES ('s3', '2026-10-22', '2026-10-22T04:00:00Z', 900, 'abandoned', 0)
                """
            )

            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s1', 't1', 1)"
            )
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s2', 't2', 0.5)"
            )
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s2', 't3', 0.5)"
            )
        }

        let history = try store.history(days: 2, endingOn: "2026-10-22")
        XCTAssertEqual(history.map(\.date), ["2026-10-22", "2026-10-21"])

        let today = history[0]
        XCTAssertEqual(today.pomodoros, 1)
        XCTAssertEqual(today.focusSeconds, 1800)
        XCTAssertEqual(today.completedTasks.map(\.title), ["任务二"])
        XCTAssertEqual(today.records.first?.tasks.count, 2)
        XCTAssertEqual(
            Set(today.records.first?.tasks.map(\.share) ?? []),
            Set([0.5])
        )

        let yesterday = history[1]
        XCTAssertEqual(yesterday.pomodoros, 1)
        XCTAssertEqual(yesterday.focusSeconds, 1500)
        XCTAssertEqual(yesterday.completedTasks.map(\.title), ["任务一"])
    }

    func testHistoryRejectsInvalidDate() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        XCTAssertThrowsError(try store.history(days: 2, endingOn: "2026/10/22")) { error in
            guard case HistoryError.invalidDate = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testReopenRemovesLatestCompletionEvent() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let task = try store.createTask(title: "任务", lane: "main")

        _ = try store.toggleTask(id: task.id)
        XCTAssertEqual(try completionCount(database), 1)

        _ = try store.toggleTask(id: task.id)
        XCTAssertEqual(try completionCount(database), 0)

        _ = try store.toggleTask(id: task.id)
        XCTAssertEqual(try completionCount(database), 1)
    }

    private func completionCount(_ database: JingliDatabase) throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_completion") ?? 0
        }
    }
}
