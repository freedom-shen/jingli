import XCTest
import JingliCore
@testable import Jingli

final class FocusStreakAppTests: XCTestCase {
    private var savedAutoDND: Any?
    private var savedLastRound: [String]?
    private var store: WorkspaceStore!
    private var model: AppModel!
    private var now: Int64 = 1_000_000

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        savedAutoDND = UserDefaults.standard.object(forKey: "jingli.autoDND")
        savedLastRound = UserDefaults.standard.stringArray(forKey: "jingli.lastRoundTaskIDs")
        UserDefaults.standard.set(false, forKey: "jingli.autoDND")
        setenv("JINGLI_TIMER_SECONDS", "1", 1)
        setenv("JINGLI_NO_NOTIFICATIONS", "1", 1)
        setenv("JINGLI_FAKE_NOW_MS", "\(now)", 1)
        store = WorkspaceStore(database: try JingliDatabase.inMemory())
        model = AppModel(store: store)
    }

    @MainActor
    override func tearDown() async throws {
        unsetenv("JINGLI_TIMER_SECONDS")
        unsetenv("JINGLI_NO_NOTIFICATIONS")
        unsetenv("JINGLI_FAKE_NOW_MS")
        if let savedAutoDND {
            UserDefaults.standard.set(savedAutoDND, forKey: "jingli.autoDND")
        } else {
            UserDefaults.standard.removeObject(forKey: "jingli.autoDND")
        }
        if let savedLastRound {
            UserDefaults.standard.set(savedLastRound, forKey: "jingli.lastRoundTaskIDs")
        } else {
            UserDefaults.standard.removeObject(forKey: "jingli.lastRoundTaskIDs")
        }
        try await super.tearDown()
    }

    @MainActor
    func testFourthConsecutiveCompletionEarnsLongBreak() throws {
        let task = try store.createTask(title: "t", lane: "temporary")

        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 1)
        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 2)
        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 3)
        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 0)

        model.startBreak()
        XCTAssertTrue(model.isOnBreak)
        XCTAssertEqual(model.breakMinutes, 25)
        XCTAssertEqual(model.breakText, "25:00")

        model.skipBreak()
        XCTAssertEqual(model.breakText, "05:00")
        XCTAssertEqual(model.breakMinutes, 5)
    }

    @MainActor
    func testAbandonResetsStreak() throws {
        let task = try store.createTask(title: "t", lane: "temporary")

        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 1)

        model.startFocus(taskIDs: [task.id])
        model.abandonFocus()
        XCTAssertEqual(model.consecutiveCompletions, 0)

        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 1)
    }

    @MainActor
    func testStartingNextRoundCancelsPendingLongBreak() throws {
        let task = try store.createTask(title: "t", lane: "temporary")

        for _ in 0..<4 {
            completeRound(with: task.id)
        }
        // 不休息直接开新一轮：长休作废；第 5 轮完成后回到 5 分钟短休。
        completeRound(with: task.id)
        XCTAssertEqual(model.consecutiveCompletions, 1)

        model.startBreak()
        XCTAssertEqual(model.breakMinutes, 5)
    }

    @MainActor
    func testStreakPersistsAcrossModelReload() throws {
        let task = try store.createTask(title: "t", lane: "temporary")
        completeRound(with: task.id)
        completeRound(with: task.id)

        let reloaded = AppModel(store: store)
        XCTAssertEqual(reloaded.consecutiveCompletions, 2)
        XCTAssertEqual(reloaded.breakMinutes, 5)
    }

    @MainActor
    private func completeRound(with taskID: String) {
        model.startFocus(taskIDs: [taskID])
        now += 60_000
        setenv("JINGLI_FAKE_NOW_MS", "\(now)", 1)
        model.tickFocus()
    }
}
