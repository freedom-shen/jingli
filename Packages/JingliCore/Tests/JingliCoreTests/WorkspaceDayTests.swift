import XCTest
import GRDB
@testable import JingliCore

final class WorkspaceDayTests: XCTestCase {
    func testGroupsAndDraftSelection() throws {
        let (store, _, t1, t2) = try makeStore()
        let groups = try store.dayStartGroups()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.tasks.count, 1)
        XCTAssertEqual(groups.last?.tasks.count, 2)

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

    func testStartedDayOnlyAcceptsTemporaryTasks() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let main = try store.createTask(title: "主线", lane: "main")
        try store.startDay(taskIDs: [main.id], today: "2026-10-22")

        XCTAssertThrowsError(
            try store.createTask(
                title: "新主线",
                lane: "main",
                plannedDate: "2026-10-22"
            )
        ) { error in
            guard case DayPlanError.mainTaskLocked = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let temporary = try store.createTask(
            title: "临时插单",
            lane: "temporary",
            plannedDate: "2026-10-22"
        )
        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertEqual(Set(snapshot.todayTasks.map(\.id)), Set([main.id, temporary.id]))
        XCTAssertEqual(snapshot.todayTasks.first { $0.id == temporary.id }?.lane, "temporary")
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

    func testToggleTaskCompletion() throws {
        let (store, _, t1, _) = try makeStore()

        let done = try store.toggleTask(id: t1.id)
        XCTAssertEqual(done?.done, true)
        XCTAssertNotNil(done?.completedAt)

        let reopened = try store.toggleTask(id: t1.id)
        XCTAssertEqual(reopened?.done, false)
        XCTAssertNil(reopened?.completedAt)
    }

    private func makeStore() throws -> (WorkspaceStore, Project, Task, Task) {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        let t1 = try store.createTask(title: "主线", projectID: project.id, lane: "main")
        let t2 = try store.createTask(title: "临时", projectID: nil, lane: "temporary")
        _ = try store.createTask(title: "未分类", projectID: nil, lane: "main")
        return (store, project, t1, t2)
    }
}

extension WorkspaceDayTests {
    func testRolloverIfNeededClearsYesterdayOncePerDay() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let yesterday = "2026-10-21"
        let today = "2026-10-22"

        let open = try store.createTask(title: "未完成", lane: "main", plannedDate: yesterday)
        let done = try store.createTask(title: "已完成", lane: "main", plannedDate: yesterday)
        _ = try store.toggleTask(id: done.id)

        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO focus_session
                    (id, session_date, started_at, duration_sec, status)
                VALUES ('s-old', ?, '2026-10-21T09:00:00Z', 1500, 'completed')
                """,
                arguments: [yesterday]
            )
            try db.execute(
                sql: "INSERT INTO day_plan (date, started) VALUES (?, 1)",
                arguments: [yesterday]
            )
            try db.execute(
                sql: "INSERT INTO setting (key, value) VALUES ('last_seen_day', ?)",
                arguments: [yesterday]
            )
        }

        XCTAssertTrue(try store.rolloverIfNeeded(today: today))
        XCTAssertFalse(try store.rolloverIfNeeded(today: today))

        let tasks = try store.listTasks(includeDone: true)
        XCTAssertNil(tasks.first { $0.id == open.id }?.plannedDate)
        XCTAssertEqual(tasks.first { $0.id == done.id }?.plannedDate, yesterday)

        XCTAssertEqual(try store.todayStats(today: today).pomodoros, 0)
        try database.queue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM focus_session"),
                1,
                "旧番茄记录保留供历史查询"
            )
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM day_plan WHERE date = ?", arguments: [yesterday]),
                1,
                "旧日计划保留"
            )
            XCTAssertEqual(
                try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = 'last_seen_day'"),
                today
            )
        }
    }

    func testRolloverIfNeededFirstLaunchJustRecordsDay() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let task = try store.createTask(title: "今天保持计划", lane: "main", plannedDate: "2026-10-22")

        XCTAssertTrue(try store.rolloverIfNeeded(today: "2026-10-22"))
        XCTAssertFalse(try store.rolloverIfNeeded(today: "2026-10-22"))

        XCTAssertEqual(
            try store.listTasks().first { $0.id == task.id }?.plannedDate,
            "2026-10-22"
        )
    }
}

extension WorkspaceDayTests {
    func testUpdateTaskTrimsTitleAndPersistsNote() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let task = try store.createTask(title: "原标题", lane: "main")

        let updated = try store.updateTask(
            id: task.id,
            title: "  新标题  ",
            note: "备注内容",
            estimate: nil
        )
        XCTAssertEqual(updated?.title, "新标题")
        XCTAssertEqual(updated?.note, "备注内容")

        let longNote = String(repeating: "字", count: 1200)
        let capped = try store.updateTask(id: task.id, title: "新标题", note: longNote, estimate: nil)
        XCTAssertEqual(capped?.note.count, 1000)

        XCTAssertThrowsError(
            try store.updateTask(id: task.id, title: "   ", note: "", estimate: nil)
        ) { error in
            guard case StoreError.emptyTitle = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testCreditTotalSumsSharedPomodorosForToday() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let task = try store.createTask(title: "共享任务", lane: "main")
        let other = try store.createTask(title: "另一件", lane: "main")

        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO focus_session
                    (id, session_date, started_at, duration_sec, status)
                VALUES ('s1', '2026-10-22', '2026-10-22T09:00:00Z', 1500, 'completed')
                """)
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s1', ?, 0.5)",
                arguments: [task.id])
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s1', ?, 0.5)",
                arguments: [other.id])
            try db.execute(
                sql: """
                INSERT INTO focus_session
                    (id, session_date, started_at, duration_sec, status)
                VALUES ('s2', '2026-10-22', '2026-10-22T10:00:00Z', 1500, 'abandoned')
                """)
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('s2', ?, 1)",
                arguments: [task.id])
        }

        XCTAssertEqual(try store.creditTotal(taskID: task.id, today: "2026-10-22"), 0.5, accuracy: 0.001)
    }
}

extension WorkspaceDayTests {
    func testTodayStatsCountsOnlyCompletedSessions() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let today = "2026-10-22"
        let first = try store.createTask(title: "写方案", lane: "main", plannedDate: today)
        let second = try store.createTask(title: "回邮件", lane: "temporary", plannedDate: today)
        _ = try store.toggleTask(id: second.id)

        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO focus_session
                    (id, session_date, started_at, duration_sec, status)
                VALUES ('done', ?, '2026-10-22T09:00:00Z', 1500, 'completed')
                """,
                arguments: [today]
            )
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('done', ?, 0.5)",
                arguments: [first.id]
            )
            try db.execute(
                sql: "INSERT INTO focus_session_task (session_id, task_id, share) VALUES ('done', ?, 0.5)",
                arguments: [second.id]
            )
            try db.execute(
                sql: """
                INSERT INTO focus_session
                    (id, session_date, started_at, duration_sec, status)
                VALUES ('gone', ?, '2026-10-22T10:00:00Z', 900, 'abandoned')
                """,
                arguments: [today]
            )
        }

        let stats = try store.todayStats(today: today)
        XCTAssertEqual(stats.pomodoros, 1)
        XCTAssertEqual(stats.focusSeconds, 1500)
        XCTAssertEqual(stats.completedTasks, 1)
        XCTAssertEqual(stats.records.count, 1)
        XCTAssertEqual(stats.records.first?.tasks.count, 2)
        XCTAssertEqual(stats.records.first?.tasks.first?.share, 0.5)
    }
}

extension WorkspaceDayTests {
    func testSaveDaySelectionAllowsClearingLastTask() throws {
        let (store, _, t1, t2) = try makeStore()
        try store.saveDaySelection(taskIDs: [t1.id, t2.id], today: "2026-10-22")
        XCTAssertEqual(try store.snapshot(today: "2026-10-22").selection.count, 2)

        XCTAssertNoThrow(try store.saveDaySelection(taskIDs: [], today: "2026-10-22"))
        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertTrue(snapshot.selection.isEmpty)
        XCTAssertFalse(snapshot.dayStarted)
    }

    func testStartDayStillRejectsEmptySelection() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        XCTAssertThrowsError(try store.startDay(taskIDs: [], today: "2026-10-22")) { error in
            guard case DayPlanError.emptySelection = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAddToTodayAppendsWithoutReplacingSelection() throws {
        let (store, _, t1, t2) = try makeStore()
        try store.saveDaySelection(taskIDs: [t1.id], today: "2026-10-22")

        let added = try store.addToToday(taskIDs: [t2.id], today: "2026-10-22")
        XCTAssertEqual(added.map(\.id), [t2.id])

        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertFalse(snapshot.dayStarted)
        XCTAssertEqual(Set(snapshot.selection), Set([t1.id, t2.id]))
        XCTAssertEqual(snapshot.todayTasks.first { $0.id == t2.id }?.lane, "temporary")
    }

    func testAddToTodayKeepsLaneAndProjectAfterDayStarted() throws {
        let (store, project, t1, _) = try makeStore()
        try store.startDay(taskIDs: [t1.id], today: "2026-10-22")

        let main = try store.createTask(title: "上线数据库", projectID: project.id, lane: "main")
        let temp = try store.createTask(title: "回邮件", lane: "temporary")
        _ = try store.addToToday(taskIDs: [main.id, temp.id], today: "2026-10-22")

        let snapshot = try store.snapshot(today: "2026-10-22")
        XCTAssertTrue(snapshot.dayStarted)
        XCTAssertEqual(snapshot.todayTasks.count, 3)
        let addedMain = snapshot.todayTasks.first { $0.id == main.id }
        XCTAssertEqual(addedMain?.lane, "main")
        XCTAssertEqual(addedMain?.projectID, project.id)
        XCTAssertEqual(snapshot.todayTasks.first { $0.id == temp.id }?.lane, "temporary")
    }

    func testAddToTodayCountsMainSlotsIncludingCompleted() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let mains = try (0..<4).map {
            try store.createTask(title: "main-\($0)", lane: "main")
        }
        try store.startDay(taskIDs: mains.map(\.id), today: "2026-10-22")
        _ = try store.toggleTask(id: mains[0].id)

        let extra = try store.createTask(title: "多出来", lane: "main")
        XCTAssertThrowsError(
            try store.addToToday(taskIDs: [extra.id], today: "2026-10-22")
        ) { error in
            guard case DayPlanError.tooManyMainTasks = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAddToTodayCountsSelectionBeforeDayStarts() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let mains = try (0..<4).map {
            try store.createTask(title: "main-\($0)", lane: "main")
        }
        try store.saveDaySelection(taskIDs: mains.map(\.id), today: "2026-10-22")
        XCTAssertEqual(try store.plannedMainCount(today: "2026-10-22"), 4)

        let extra = try store.createTask(title: "第五个", lane: "main")
        XCTAssertThrowsError(
            try store.addToToday(taskIDs: [extra.id], today: "2026-10-22")
        ) { error in
            guard case DayPlanError.tooManyMainTasks = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAddToTodaySkipsDuplicatesAndRejectsDone() throws {
        let (store, _, t1, _) = try makeStore()
        try store.startDay(taskIDs: [t1.id], today: "2026-10-22")

        let already = try store.addToToday(taskIDs: [t1.id], today: "2026-10-22")
        XCTAssertTrue(already.isEmpty)

        let done = try store.createTask(title: "已完成", lane: "temporary")
        _ = try store.toggleTask(id: done.id)
        XCTAssertThrowsError(
            try store.addToToday(taskIDs: [done.id], today: "2026-10-22")
        ) { error in
            guard case DayPlanError.taskCompleted = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
