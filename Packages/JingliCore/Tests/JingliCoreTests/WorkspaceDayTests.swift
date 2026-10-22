import XCTest
import GRDB
@testable import JingliCore

final class WorkspaceDayTests: XCTestCase {
    func testGroupsAndDraftSelection() throws {
        let (store, _, t1, t2) = try makeStore()
        let groups = try store.dayStartGroups()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.tasks.count, 2)

        try store.saveDaySelection(taskIDs: [t1.id, t2.id], today: "2026-10-22")
        let snapshot = try store.snapshot(today: "2026-10-22")

        XCTAssertFalse(snapshot.dayStarted)
        XCTAssertEqual(Set(snapshot.selection), Set([t1.id, t2.id]))
    }

    func testStartDayMovesSelectedAndClearsUnselected() throws {
        let (store, _, t1, t2) = try makeStore()
        let t3 = try store.createTask(title: "未选", projectID: nil, lane: "main")

        try store.startDay(taskIDs: [t1.id, t2.id], today: "2026-10-22")

        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertTrue(snapshot.dayStarted)
        XCTAssertEqual(Set(snapshot.todayTasks.map(\.id)), Set([t1.id, t2.id]))
        XCTAssertEqual(snapshot.todayTasks.first?.lane, "main")

        let all = try store.listTasks(includeDone: true)
        XCTAssertNil(all.first { $0.id == t3.id }?.plannedDate)
    }

    func testStartDayRejectsTooManyMainTasks() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let tasks = try (0..<5).map {
            try store.createTask(title: "main-\($0)", lane: "main")
        }

        XCTAssertThrowsError(
            try store.startDay(taskIDs: tasks.map(\.id), today: "2026-10-22")
        ) { error in
            guard case DayPlanError.tooManyMainTasks = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCompletedMainStillOccupiesSlot() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        let completed = try (0..<3).map {
            try store.createTask(
                title: "done-\($0)",
                lane: "main",
                plannedDate: "2026-10-22"
            )
        }
        for task in completed {
            try database.queue.write { db in
                try db.execute(
                    sql: "UPDATE task SET done = 1, completed_at = ? WHERE id = ?",
                    arguments: ["2026-10-22T10:00:00Z", task.id]
                )
            }
        }
        let selected = try (0..<2).map {
            try store.createTask(title: "new-\($0)", lane: "main")
        }

        XCTAssertThrowsError(
            try store.startDay(taskIDs: selected.map(\.id), today: "2026-10-22")
        ) { error in
            guard case DayPlanError.tooManyMainTasks = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testResetDayClearsPlanButKeepsTasks() throws {
        let (store, _, t1, t2) = try makeStore()
        try store.startDay(taskIDs: [t1.id, t2.id], today: "2026-10-22")
        try store.resetDay(today: "2026-10-22")

        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertFalse(snapshot.dayStarted)
        XCTAssertTrue(snapshot.todayTasks.isEmpty)
        XCTAssertEqual(try store.taskCount(), 3)
    }

    private func makeStore() throws -> (WorkspaceStore, Project, Task, Task) {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        let t1 = try store.createTask(title: "主线", projectID: project.id, lane: "main")
        let t2 = try store.createTask(title: "临时", projectID: project.id, lane: "temporary")
        _ = try store.createTask(title: "未分类", projectID: nil, lane: "main")
        return (store, project, t1, t2)
    }
}
