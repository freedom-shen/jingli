import Foundation

/// 只管理「今天」的日期键，格式 `yyyy-MM-dd`。
public enum DayKey {
    private final class State: @unchecked Sendable {
        var startHour = 8
    }

    private static let state = State()

    /// 一天的起点（小时，0–23）。默认 8：在此之前仍算前一天，
    /// 避免凌晨还在工作时被切走。由 App 启动时从设置写入。
    public static var startHour: Int {
        get { state.startHour }
        set { state.startHour = max(0, min(23, newValue)) }
    }

    public static func make(from date: Date = Date(), calendar: Calendar = .current) -> String {
        let shifted = startHour == 0
            ? date
            : (calendar.date(byAdding: .hour, value: -startHour, to: date) ?? date)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func isToday(_ key: String, calendar: Calendar = .current) -> Bool {
        key == make(calendar: calendar)
    }
}
