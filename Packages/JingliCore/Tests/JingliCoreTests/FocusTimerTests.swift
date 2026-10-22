import XCTest
@testable import JingliCore

final class FocusTimerTests: XCTestCase {
    private let duration = 25 * 60 * 1000

    func testPrepareDeduplicatesAndRejectsEmpty() {
        let timer = FocusTimer(taskIDs: ["a", "a", "b"], sessionDate: "2026-10-22")
        XCTAssertEqual(timer?.taskIDs, ["a", "b"])
        XCTAssertEqual(timer?.phase, .ready)
        XCTAssertNil(FocusTimer(taskIDs: [], sessionDate: "2026-10-22"))
    }

    func testStartAndRemaining() throws {
        var timer = try XCTUnwrap(FocusTimer(taskIDs: ["a"], sessionDate: "2026-10-22"))
        timer.start(now: 1_000, sessionID: "s1")

        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(now: 1_000), duration)
        XCTAssertEqual(timer.remaining(now: 751_000), 750_000)
        XCTAssertEqual(FocusTimer.format(timer.remaining(now: 751_000)), "12:30")
    }

    func testPauseResumeAndFinish() throws {
        var timer = try XCTUnwrap(FocusTimer(taskIDs: ["a"], sessionDate: "2026-10-22"))
        timer.start(now: 1_000, sessionID: "s1")
        timer.pause(now: 751_000)

        XCTAssertEqual(timer.phase, .paused)
        XCTAssertEqual(timer.remainingMs, 750_000)
        XCTAssertEqual(timer.remaining(now: 2_000_000), 750_000)

        timer.resume(now: 2_000_000)
        XCTAssertEqual(timer.phase, .running)
        XCTAssertEqual(timer.remaining(now: 2_500_000), 250_000)

        timer.tick(now: 2_750_000)
        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.remaining(now: 2_750_000), 0)
        XCTAssertNil(timer.endsAt)
    }

    func testSleepWakeFinishesFromEndsAt() throws {
        var timer = try XCTUnwrap(FocusTimer(taskIDs: ["a"], sessionDate: "2026-10-22"))
        timer.start(now: 1_000, sessionID: "s1")
        timer.tick(now: 1_000 + Int64(duration) + 60_000)

        XCTAssertEqual(timer.phase, .finished)
        XCTAssertEqual(timer.remainingMs, 0)
    }

    func testAddAndRemoveParticipants() throws {
        var timer = try XCTUnwrap(FocusTimer(taskIDs: ["a"], sessionDate: "2026-10-22"))
        timer.start(now: 1_000, sessionID: "s1")

        let added = timer.addingTask("b")
        XCTAssertEqual(added.taskIDs, ["a", "b"])
        XCTAssertEqual(added.remaining(now: 751_000), timer.remaining(now: 751_000))

        let removed = added.removingTask("a")
        XCTAssertEqual(removed?.taskIDs, ["b"])
        XCTAssertNil(removed?.removingTask("b"))
    }

    func testFormat() {
        XCTAssertEqual(FocusTimer.format(0), "00:00")
        XCTAssertEqual(FocusTimer.format(1_000), "00:01")
        XCTAssertEqual(FocusTimer.format(1_500_000), "25:00")
        XCTAssertEqual(FocusTimer.format(761_000), "12:41")
    }

    func testFocusModeFlags() throws {
        var timer = try XCTUnwrap(FocusTimer(taskIDs: ["a"], sessionDate: "2026-10-22"))
        timer.setFocusMode(on: true, owned: false)
        XCTAssertTrue(timer.focusModeOn)
        XCTAssertFalse(timer.focusModeOwned)
    }
}
