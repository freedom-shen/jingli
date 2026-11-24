import XCTest
import GRDB
@testable import JingliCore

/// 「正在进行」的跨端可见性：计时器本身是本地状态，但开始/暂停/恢复会镜像进
/// `focus_session`（status = running / paused），另一台设备拉下来就能显示。
/// 重点是不能影响统计口径（只有 completed 才算番茄）。
final class RemoteFocusTests: XCTestCase {
    private struct Device {
        let database: JingliDatabase
        let store: WorkspaceStore
        let sync: SyncStore
        let timers: FocusTimerStore
    }

    private func makeDevice() throws -> Device {
        let database = try JingliDatabase.inMemory()
        return Device(
            database: database,
            store: WorkspaceStore(database: database),
            sync: SyncStore(database: database),
            timers: FocusTimerStore(database: database)
        )
    }

    private var nowMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func startedTimer(taskIDs: [String]) throws -> FocusTimer {
        var timer = try XCTUnwrap(
            FocusTimer(taskIDs: taskIDs, sessionDate: DayKey.make())
        )
        timer.start(now: nowMs, sessionID: UUID().uuidString)
        return timer
    }

    func testRunningSessionIsVisibleOnOtherDeviceWithoutCountingPomodoro() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "写方案", lane: "main")

        let timer = try startedTimer(taskIDs: [task.id])
        try a.timers.saveActive(timer)

        // A 的这轮镜像进了 focus_session，并产生可同步的变更
        XCTAssertGreaterThan(try a.sync.pendingCount(), 0)
        try b.sync.apply(try a.sync.allChanges())

        let remote = try XCTUnwrap(try b.store.remoteFocusSession())
        XCTAssertEqual(remote.sessionID, timer.sessionID)
        XCTAssertEqual(remote.taskTitles, ["写方案"])
        XCTAssertFalse(remote.isPaused)
        XCTAssertNotNil(remote.endsAt)
        XCTAssertGreaterThan(remote.remainingMs(now: Date()), 0)

        // 进行中不算番茄
        XCTAssertEqual(try b.store.todayStats().pomodoros, 0)
        XCTAssertEqual(try b.store.creditTotals(), [:])

        // 完成后：对面不再是「正在进行」，且正好算 1 个番茄
        var finished = timer
        finished.tick(now: (timer.startedAt ?? nowMs) + Int64(FocusTimer.defaultDurationMs))
        XCTAssertEqual(finished.phase, .finished)
        _ = try a.timers.complete(finished)
        try b.sync.apply(try a.sync.allChanges())

        XCTAssertNil(try b.store.remoteFocusSession())
        XCTAssertEqual(try b.store.todayStats().pomodoros, 1)
        XCTAssertEqual(try b.store.creditTotals()[task.id], 1)
    }

    func testPausedSessionIsVisibleAsPaused() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "查资料", lane: "temporary")

        var timer = try startedTimer(taskIDs: [task.id])
        timer.pause(now: (timer.startedAt ?? nowMs) + 60_000)
        try a.timers.saveActive(timer)
        try b.sync.apply(try a.sync.allChanges())

        let remote = try XCTUnwrap(try b.store.remoteFocusSession())
        XCTAssertTrue(remote.isPaused)
        XCTAssertNil(remote.endsAt, "暂停状态没有倒计时")
        XCTAssertEqual(remote.remainingText(), "已暂停")

        // 恢复后对面又能看到倒计时
        var resumed = timer
        resumed.resume(now: (timer.startedAt ?? nowMs) + 120_000)
        try a.timers.saveActive(resumed)
        try b.sync.apply(try a.sync.allChanges())
        let again = try XCTUnwrap(try b.store.remoteFocusSession())
        XCTAssertFalse(again.isPaused)
        XCTAssertNotNil(again.endsAt)
    }

    func testAbandonedSessionIsNotShownAndNotCounted() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "放弃的一轮", lane: "temporary")

        let timer = try startedTimer(taskIDs: [task.id])
        try a.timers.saveActive(timer)
        try b.sync.apply(try a.sync.allChanges())
        XCTAssertNotNil(try b.store.remoteFocusSession())

        try a.timers.clearActive()
        try b.sync.apply(try a.sync.allChanges())

        XCTAssertNil(try b.store.remoteFocusSession(), "放弃的一轮不能一直挂在对面")
        XCTAssertEqual(try b.store.todayStats().pomodoros, 0)
    }

    func testLocalSessionIsExcluded() throws {
        let a = try makeDevice()
        let task = try a.store.createTask(title: "自己的", lane: "main")
        let timer = try startedTimer(taskIDs: [task.id])
        try a.timers.saveActive(timer)

        XCTAssertNil(
            try a.store.remoteFocusSession(excluding: timer.sessionID),
            "本机自己的计时器不能被当成「另一台设备」"
        )
        XCTAssertNotNil(try a.store.remoteFocusSession())
    }

    func testStaleRunningSessionIsHidden() throws {
        let a = try makeDevice()
        let b = try makeDevice()
        let task = try a.store.createTask(title: "对面崩了", lane: "main")

        let timer = try startedTimer(taskIDs: [task.id])
        try a.timers.saveActive(timer)
        try b.sync.apply(try a.sync.allChanges())

        // 预计结束时间已经过去很久（对面异常退出、没来得及收尾）
        let past = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-3600)
        )
        try b.database.queue.write { db in
            try db.execute(
                sql: "UPDATE focus_session SET ended_at = ? WHERE status = 'running'",
                arguments: [past]
            )
        }
        XCTAssertNil(try b.store.remoteFocusSession())
    }
}
