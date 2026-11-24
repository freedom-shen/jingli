import XCTest
import GRDB
@testable import JingliCore

final class SyncTests: XCTestCase {
    private struct Device {
        let database: JingliDatabase
        let store: WorkspaceStore
        let sync: SyncStore
    }

    private func makeDevice() throws -> Device {
        let database = try JingliDatabase.inMemory()
        return Device(
            database: database,
            store: WorkspaceStore(database: database),
            sync: SyncStore(database: database)
        )
    }

    // MARK: - Change capture

    func testCreateTaskEmitsFieldChanges() throws {
        let device = try makeDevice()
        let task = try device.store.createTask(
            title: "写周报",
            lane: "main",
            estimate: 3
        )

        let changes = try device.sync.allChanges()
            .filter { $0.entity == "task" && $0.entityID == task.id }
        let fields = Set(changes.map(\.field))

        XCTAssertTrue(fields.contains("title"))
        XCTAssertTrue(fields.contains("project_id"))
        XCTAssertTrue(fields.contains("lane"))
        XCTAssertTrue(fields.contains("planned_date"))
        XCTAssertTrue(fields.contains("note"))
        XCTAssertTrue(fields.contains("done"))
        XCTAssertTrue(fields.contains("created_at"))
        XCTAssertTrue(fields.contains("estimate"))
        XCTAssertFalse(fields.contains("sort_order"), "本地排序不参与同步")
        XCTAssertEqual(
            changes.first { $0.field == "title" }?.valueJSON,
            "\"写周报\""
        )
        XCTAssertTrue(changes.allSatisfy { !$0.rev.isEmpty })
        XCTAssertEqual(try device.sync.pendingCount(), changes.count)
    }

    func testUpdateOnlyEmitsChangedField() throws {
        let device = try makeDevice()
        let task = try device.store.createTask(
            title: "写周报",
            lane: "temporary",
            estimate: 3
        )
        let baseline = try device.sync.lastSeq()

        _ = try device.store.updateTask(
            id: task.id,
            title: "写周报",
            note: "补一段背景",
            estimate: 3
        )

        let changes = try device.sync.allChanges(after: baseline)
            .filter { $0.entity == "task" && $0.entityID == task.id }
        XCTAssertEqual(changes.map(\.field), ["note"])
        XCTAssertEqual(changes.first?.valueJSON, "\"补一段背景\"")
    }

    func testDeleteEmitsTombstone() throws {
        let device = try makeDevice()
        let task = try device.store.createTask(title: "删我")
        let baseline = try device.sync.lastSeq()

        _ = try device.store.deleteTask(id: task.id)

        let changes = try device.sync.allChanges(after: baseline)
            .filter { $0.entity == "task" && $0.entityID == task.id }
        let deletion = try XCTUnwrap(changes.first { $0.field == "__deleted" })
        XCTAssertEqual(deletion.valueJSON, "true")
        XCTAssertNotNil(
            try device.sync.tombstoneRev(entity: "task", entityID: task.id)
        )
    }

    func testRolloverDoesNotEmitChanges() throws {
        let device = try makeDevice()
        let today = DayKey.make()
        let yesterday = DayKey.make(
            from: Date().addingTimeInterval(-24 * 60 * 60)
        )
        let task = try device.store.createTask(
            title: "昨天的计划",
            lane: "main",
            plannedDate: yesterday
        )
        let baseline = try device.sync.lastSeq()

        try device.database.rollover(to: today)

        XCTAssertNil(
            try device.store.listTasks(includeDone: true)
                .first { $0.id == task.id }?.plannedDate
        )
        XCTAssertEqual(
            try device.sync.lastSeq(),
            baseline,
            "rollover 是本地派生状态，不应产生同步变更"
        )
    }

    func testDaySelectionDiffOnlyEmitsAddAndRemove() throws {
        let device = try makeDevice()
        let date = "2026-10-22"
        let t1 = try device.store.createTask(title: "一", lane: "main")
        let t2 = try device.store.createTask(title: "二", lane: "main")
        let t3 = try device.store.createTask(title: "三", lane: "main")

        try device.store.saveDaySelection(taskIDs: [t1.id, t2.id], today: date)
        let baseline = try device.sync.lastSeq()
        try device.store.saveDaySelection(taskIDs: [t1.id, t3.id], today: date)

        let changes = try device.sync.allChanges(after: baseline)
            .filter { $0.entity == "dayPlanTask" }
        let byID = Dictionary(grouping: changes, by: \.entityID)

        XCTAssertEqual(
            byID["\(date)|\(t2.id)"]?.last { $0.field == "__present" }?.valueJSON,
            "false"
        )
        XCTAssertEqual(
            byID["\(date)|\(t3.id)"]?.last { $0.field == "__present" }?.valueJSON,
            "true"
        )
        XCTAssertNil(byID["\(date)|\(t1.id)"], "未变化的成员不应重写")
    }

    func testSettingsAndTaskOrderAreNotCaptured() throws {
        let device = try makeDevice()
        let task = try device.store.createTask(title: "任务")
        let baseline = try device.sync.lastSeq()

        try device.store.setSettingValue("focus_owned", "1")
        try device.store.saveTaskOrder(
            scope: "today:2026-10-22:main",
            orderedIDs: [task.id]
        )

        let changes = try device.sync.allChanges(after: baseline)
        XCTAssertFalse(changes.contains { $0.entity == "setting" })
        XCTAssertFalse(changes.contains { $0.entity == "taskOrder" })
    }

    func testFocusSessionCompletionDoesNotEmitDelete() throws {
        let device = try makeDevice()
        let task = try device.store.createTask(title: "专注", lane: "temporary")
        let timerStore = FocusTimerStore(database: device.database)
        var timer = try XCTUnwrap(
            FocusTimer(taskIDs: [task.id], sessionDate: DayKey.make())
        )
        timer.start(now: 1_000, sessionID: "s1")
        timer.tick(now: 1_000 + Int64(timer.durationMs) + 1)

        let baseline = try device.sync.lastSeq()
        _ = try XCTUnwrap(try timerStore.complete(timer))

        let changes = try device.sync.allChanges(after: baseline)
            .filter { $0.entity == "focusSession" && $0.entityID == "s1" }
        XCTAssertFalse(changes.contains { $0.field == "__deleted" })
        XCTAssertTrue(changes.contains { $0.field == "session_date" })
    }

    // MARK: - Two-device merge

    func testDifferentFieldsMergeInsteadOfOverwriting() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let project = try a.store.createProject(name: "工作")
        let task = try a.store.createTask(
            title: "写周报",
            projectID: project.id,
            lane: "main"
        )
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        _ = try a.store.updateTask(
            id: task.id,
            title: "写周报 v2",
            note: "",
            estimate: nil
        )
        _ = try b.store.updateTask(
            id: task.id,
            title: "写周报",
            note: "B 补的备注",
            estimate: nil
        )

        try b.sync.apply(try a.sync.pendingChanges())
        try a.sync.apply(try b.sync.pendingChanges())

        let finalA = try XCTUnwrap(
            try a.store.listTasks(includeDone: true).first { $0.id == task.id }
        )
        let finalB = try XCTUnwrap(
            try b.store.listTasks(includeDone: true).first { $0.id == task.id }
        )
        XCTAssertEqual(finalA.title, "写周报 v2")
        XCTAssertEqual(finalA.note, "B 补的备注")
        XCTAssertEqual(finalB.title, "写周报 v2")
        XCTAssertEqual(finalB.note, "B 补的备注")
    }

    func testProjectDeleteClearsTaskReference() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let project = try a.store.createProject(name: "工作")
        let task = try a.store.createTask(
            title: "任务",
            projectID: project.id,
            lane: "main"
        )
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        try a.store.deleteProject(id: project.id)
        try b.sync.apply(try a.sync.pendingChanges())

        let taskOnB = try XCTUnwrap(
            try b.store.listTasks(includeDone: true).first { $0.id == task.id }
        )
        XCTAssertNil(taskOnB.projectID, "删项目后任务应回到未分类")
    }

    func testDeleteWinsOverStaleOfflineEdit() throws {        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "删我")
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        _ = try b.store.updateTask(
            id: task.id,
            title: "删我",
            note: "离线备注",
            estimate: nil
        )
        let staleNote = try b.sync.pendingChanges()
        try a.sync.apply(staleNote)

        _ = try a.store.deleteTask(id: task.id)
        let deletion = try a.sync.pendingChanges()
        try b.sync.apply(deletion)

        // 再投递一次删除前产生的旧备注：删任务后不应复活。
        try a.sync.apply(staleNote)

        XCTAssertNil(
            try a.store.listTasks(includeDone: true).first { $0.id == task.id }
        )
        XCTAssertNil(
            try b.store.listTasks(includeDone: true).first { $0.id == task.id }
        )
    }

    func testDayPlanUnionThenRemovalConverges() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let date = "2026-10-22"
        let t1 = try a.store.createTask(title: "一", lane: "main")
        let t2 = try a.store.createTask(title: "二", lane: "main")
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        try a.store.saveDaySelection(taskIDs: [t1.id], today: date)
        try b.store.saveDaySelection(taskIDs: [t1.id, t2.id], today: date)
        try b.sync.apply(try a.sync.pendingChanges())
        try a.sync.apply(try b.sync.pendingChanges())

        XCTAssertEqual(
            Set(try a.store.snapshot(today: date).selection),
            Set([t1.id, t2.id]),
            "两边各自加入的任务应取并集"
        )
        XCTAssertEqual(
            Set(try b.store.snapshot(today: date).selection),
            Set([t1.id, t2.id])
        )

        try a.store.saveDaySelection(taskIDs: [t2.id], today: date)
        try b.sync.apply(try a.sync.pendingChanges())
        XCTAssertEqual(
            Set(try b.store.snapshot(today: date).selection),
            Set([t2.id]),
            "移除要能传播，不能被并集加回来"
        )
    }

    func testRolloverDoesNotClobberRemoteTodayPlan() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let today = DayKey.make()
        let yesterday = DayKey.make(
            from: Date().addingTimeInterval(-24 * 60 * 60)
        )
        let task = try a.store.createTask(
            title: "今天要做",
            lane: "main",
            plannedDate: yesterday
        )
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        // B 离线跨天：本地清掉昨日计划，但不应产生待推送变更。
        try b.database.rollover(to: today)
        XCTAssertNil(
            try b.store.listTasks(includeDone: true)
                .first { $0.id == task.id }?.plannedDate
        )
        XCTAssertEqual(try b.sync.pendingCount(), 0)

        // A 把任务排到今天，并同步给 B。
        try a.store.startDay(taskIDs: [task.id], today: today)
        try b.sync.apply(try a.sync.pendingChanges())

        XCTAssertEqual(
            try b.store.listTasks(includeDone: true)
                .first { $0.id == task.id }?.plannedDate,
            today,
            "B 的 rollover 不能覆盖 A 今天刚排好的计划"
        )
    }

    func testPastPlannedDateChangeIsIgnored() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let today = DayKey.make()
        let yesterday = DayKey.make(
            from: Date().addingTimeInterval(-24 * 60 * 60)
        )
        let task = try a.store.createTask(
            title: "今天要做",
            lane: "main",
            plannedDate: today
        )
        try b.sync.apply(try a.sync.allChanges())
        try a.sync.markPushed(try a.sync.pendingChanges())

        try a.database.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET planned_date = ? WHERE id = ?",
                arguments: [yesterday, task.id]
            )
        }
        try b.sync.apply(try a.sync.pendingChanges())

        XCTAssertEqual(
            try b.store.listTasks(includeDone: true)
                .first { $0.id == task.id }?.plannedDate,
            today,
            "过去的 planned_date 是离线端迟到的旧值，不能把任务拉回昨天"
        )
    }
}

// MARK: - 外键没到时的重试（sync_retry）

extension SyncTests {
    func testForeignKeySkippedChangeIsKeptAndReplayed() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let date = "2026-10-22"

        let task = try a.store.createTask(title: "先建的", lane: "main")
        try a.store.saveDaySelection(taskIDs: [task.id], today: date)

        // 只把「今日计划成员」推过去，task 本身还没到 → 外键失败
        let planOnly = try a.sync.allChanges().filter { $0.entity == "dayPlanTask" }
        XCTAssertFalse(planOnly.isEmpty)
        let skipped = try b.sync.apply(planOnly)
        XCTAssertEqual(skipped.count, planOnly.count, "外键没到的变更应被记下来")
        XCTAssertEqual(try b.sync.pendingRetryCount(), planOnly.count)
        XCTAssertTrue(try b.store.snapshot(today: date).selection.isEmpty)

        // 依赖到了：把 task 补上，再重放
        let taskOnly = try a.sync.allChanges().filter { $0.entity == "task" || $0.entity == "project" }
        try b.sync.apply(taskOnly)
        let replayed = try b.sync.retryPending()
        XCTAssertEqual(replayed, planOnly.count, "重放应全部成功")
        XCTAssertEqual(try b.sync.pendingRetryCount(), 0)
        XCTAssertEqual(Set(try b.store.snapshot(today: date).selection), Set([task.id]))
    }

    func testRetryKeepsChangeWhenDependencyStillMissing() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let date = "2026-10-22"
        let task = try a.store.createTask(title: "还是没到", lane: "main")
        try a.store.saveDaySelection(taskIDs: [task.id], today: date)

        let planOnly = try a.sync.allChanges().filter { $0.entity == "dayPlanTask" }
        _ = try b.sync.apply(planOnly)

        XCTAssertEqual(try b.sync.retryPending(), 0, "依赖还没到，重放不该成功")
        XCTAssertEqual(try b.sync.pendingRetryCount(), planOnly.count, "失败的记录要留着")
    }
}

// MARK: - 建行需要的 NOT NULL 字段还没到时不能被整批回滚

extension SyncTests {
    /// 真机踩到的坑：`task_completion` 的 `task_id` 那条先被外键挡进重试队列，
    /// 随后单独到达的 `completed_at` 变更会去建行，`task_id` 只能是 NULL →
    /// NOT NULL 约束抛错 → 整批 apply 回滚 → 游标永不推进 → 设备永久卡死，
    /// 表现为「同步完成 错误=…」但库一直是旧的。
    func testCompletedAtBeforeTaskIDIsStashedInsteadOfAbortingBatch() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "打卡", lane: "temporary")
        try a.store.toggleTask(id: task.id)

        let changes = try a.sync.allChanges()
        let completion = changes.filter { $0.entity == "taskCompletion" }
        let taskIDChange = try XCTUnwrap(completion.first { $0.field == "task_id" })
        let completedAtChange = try XCTUnwrap(completion.first { $0.field == "completed_at" })
        let completedAt = try XCTUnwrap(
            try JSONDecoder().decode(String.self, from: Data(completedAtChange.valueJSON.utf8))
        )

        // B 已经有任务本体，但 task_completion 的 task_id 那条还没到。
        try b.sync.apply(changes.filter { $0.entity == "task" })

        // 只有 completed_at 到达：这条应该被压进重试队列，而不是把整批打回去。
        let skipped = try b.sync.apply([completedAtChange])
        XCTAssertEqual(skipped.map(\.changeID), [completedAtChange.changeID])
        XCTAssertEqual(try b.sync.pendingRetryCount(), 1)

        // 事务没被毒死：紧接着的 task_id 变更要能正常落地，游标才有机会推进。
        let after = try b.sync.apply([taskIDChange])
        XCTAssertTrue(after.isEmpty)
        let row = try b.database.queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT task_id, completed_at FROM task_completion WHERE id = ?",
                arguments: [completedAtChange.entityID]
            )
        }
        XCTAssertEqual(row?["task_id"] as String?, task.id)

        // 字段补齐后重放，把真实完成时间补回去。
        XCTAssertEqual(try b.sync.retryPending(), 1)
        XCTAssertEqual(try b.sync.pendingRetryCount(), 0)
        let fixed = try b.database.queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT task_id, completed_at FROM task_completion WHERE id = ?",
                arguments: [completedAtChange.entityID]
            )
        }
        XCTAssertEqual(fixed?["task_id"] as String?, task.id)
        XCTAssertEqual(fixed?["completed_at"] as String?, completedAt)
    }
}
