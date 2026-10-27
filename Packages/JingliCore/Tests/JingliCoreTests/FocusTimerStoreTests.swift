import XCTest
import GRDB
@testable import JingliCore

final class FocusTimerStoreTests: XCTestCase {
    func testSaveAndLoadActive() throws {
        let (database, tasks) = try makeDatabase()
        let timerStore = FocusTimerStore(database: database)
        var timer = try XCTUnwrap(
            FocusTimer(taskIDs: [tasks[0].id, tasks[1].id], sessionDate: "2026-10-22")
        )
        timer.start(now: 1_000, sessionID: "s1")

        try timerStore.saveActive(timer)

        let loaded = try timerStore.loadActive(today: "2026-10-22")
        XCTAssertEqual(loaded?.sessionID, "s1")
        XCTAssertEqual(loaded?.taskIDs, [tasks[0].id, tasks[1].id])
        XCTAssertNil(try timerStore.loadActive(today: "2026-10-23"))
    }

    func testCompleteWritesSessionAndShares() throws {
        let (database, tasks) = try makeDatabase()
        let timerStore = FocusTimerStore(database: database)
        var timer = try XCTUnwrap(
            FocusTimer(taskIDs: [tasks[0].id, tasks[1].id], sessionDate: "2026-10-22")
        )
        timer.start(now: 1_000, sessionID: "s2")
        timer.tick(now: 1_000 + Int64(timer.durationMs) + 1)

        let completion = try XCTUnwrap(try timerStore.complete(timer))

        XCTAssertEqual(completion.taskIDs.count, 2)
        XCTAssertEqual(completion.shares[tasks[0].id], 0.5)
        XCTAssertEqual(completion.shares[tasks[1].id], 0.5)

        try database.queue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_session WHERE id = ?", arguments: ["s2"]),
                1
            )
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_session_task WHERE session_id = ?", arguments: ["s2"]),
                2
            )
            XCTAssertEqual(
                try Double.fetchOne(
                    db,
                    sql: "SELECT share FROM focus_session_task WHERE session_id = ? AND task_id = ?",
                    arguments: ["s2", tasks[0].id]
                ),
                0.5
            )
            XCTAssertNil(
                try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = 'active_timer'")
            )
        }
    }

    private func makeDatabase() throws -> (JingliDatabase, [Task]) {
        let database = try JingliDatabase.inMemory()
        let workspace = WorkspaceStore(database: database)
        let project = try workspace.createProject(name: "工作")
        let tasks = try [
            workspace.createTask(title: "A", projectID: project.id, lane: "main"),
            workspace.createTask(title: "B", projectID: nil, lane: "temporary")
        ]
        return (database, tasks)
    }
}
