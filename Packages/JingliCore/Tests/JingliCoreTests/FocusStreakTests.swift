import XCTest
@testable import JingliCore

final class FocusStreakTests: XCTestCase {
    func testCountsCompletionsUpToThreshold() {
        var streak = FocusStreak()
        var earned = false

        (streak, earned) = streak.completed()
        XCTAssertEqual(streak.count, 1)
        XCTAssertFalse(earned)

        (streak, earned) = streak.completed()
        XCTAssertEqual(streak.count, 2)
        XCTAssertFalse(earned)

        (streak, earned) = streak.completed()
        XCTAssertEqual(streak.count, 3)
        XCTAssertFalse(earned)
    }

    func testFourthCompletionEarnsLongBreakAndWraps() {
        var streak = FocusStreak(count: 3)
        let (next, earned) = streak.completed()
        streak = next

        XCTAssertTrue(earned)
        XCTAssertEqual(streak.count, 0)
    }

    func testCounterRestartsAfterLongBreak() {
        var streak = FocusStreak(count: 3)
        (streak, _) = streak.completed()
        XCTAssertEqual(streak.count, 0)

        let (next, earned) = streak.completed()
        streak = next
        XCTAssertFalse(earned)
        XCTAssertEqual(streak.count, 1)
    }

    func testResetClearsStreak() {
        XCTAssertEqual(FocusStreak(count: 3).reset().count, 0)
        XCTAssertEqual(FocusStreak().reset().count, 0)
    }

    func testNegativeCountClampsToZero() {
        XCTAssertEqual(FocusStreak(count: -2).count, 0)
    }
}
