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
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9, minute: 0))!
        let key = DayKey.make(from: date, calendar: calendar)
        XCTAssertTrue(DayKey.isToday(key, calendar: calendar))
        XCTAssertFalse(DayKey.isToday("2026-10-21", calendar: calendar))
    }
}
