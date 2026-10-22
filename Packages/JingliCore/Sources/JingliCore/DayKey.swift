import Foundation

/// 只管理「今天」的日期键，格式 `yyyy-MM-dd`。
public enum DayKey {
    public static func make(from date: Date = Date(), calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func isToday(_ key: String, calendar: Calendar = .current) -> Bool {
        key == make(calendar: calendar)
    }
}
