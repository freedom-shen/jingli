import XCTest
@testable import JingliCore

final class DayKeyTests: XCTestCase {
    func testDayKeyFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 23, minute: 50))!
        XCTAssertEqual(DayKey.make(from: date, calendar: calendar), "2026-10-22")
    }

    func testIsToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date()
        let key = DayKey.make(from: now, calendar: calendar)
        XCTAssertTrue(DayKey.isToday(key, calendar: calendar))

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let yesterdayKey = DayKey.make(from: yesterday, calendar: calendar)
        XCTAssertFalse(DayKey.isToday(yesterdayKey, calendar: calendar))
    }

    func testStartHourShiftsDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let previous = DayKey.startHour
        defer { DayKey.startHour = previous }

        DayKey.startHour = 8
        let twoAM = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 23, hour: 2)
        )!
        XCTAssertEqual(DayKey.make(from: twoAM, calendar: calendar), "2026-10-22")

        let eightAM = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 23, hour: 8)
        )!
        XCTAssertEqual(DayKey.make(from: eightAM, calendar: calendar), "2026-10-23")

        DayKey.startHour = 0
        let midnightish = calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 23, hour: 0, minute: 30)
        )!
        XCTAssertEqual(DayKey.make(from: midnightish, calendar: calendar), "2026-10-23")
    }
}
