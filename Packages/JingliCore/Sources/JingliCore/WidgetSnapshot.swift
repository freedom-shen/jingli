import Foundation
import GRDB

/// Widget 只读用的今日快照。Widget 进程不写库，也不跑迁移。
public struct WidgetSnapshot: Sendable, Equatable {
    public let pomodoros: Int
    public let focusMinutes: Int
    public let mainTotal: Int
    public let mainOpen: Int
    public let tempOpen: Int
    public let nextTitle: String?

    public init(
        pomodoros: Int, focusMinutes: Int,
        mainTotal: Int, mainOpen: Int, tempOpen: Int, nextTitle: String?
    ) {
        self.pomodoros = pomodoros
        self.focusMinutes = focusMinutes
        self.mainTotal = mainTotal
        self.mainOpen = mainOpen
        self.tempOpen = tempOpen
        self.nextTitle = nextTitle
    }
}

public enum WidgetData {
    /// 只读打开 App Group 里的库；打不开就返回 nil（Widget 显示占位）。
    public static func load(containerURL: URL?, today: String = DayKey.make()) -> WidgetSnapshot? {
        guard let containerURL else { return nil }
        let databaseURL = containerURL
            .appendingPathComponent("Jingli", isDirectory: true)
            .appendingPathComponent("jingli.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        var configuration = Configuration()
        configuration.readonly = true
        guard let queue = try? DatabaseQueue(path: databaseURL.path, configuration: configuration) else {
            return nil
        }

        return try? queue.read { db in
            let pomodoros = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM focus_session WHERE session_date = ? AND status = 'completed'",
                arguments: [today]
            ) ?? 0

            let seconds = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(duration_sec), 0) FROM focus_session WHERE session_date = ? AND status = 'completed'",
                arguments: [today]
            ) ?? 0

            let mainTotal = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE planned_date = ? AND lane = 'main'",
                arguments: [today]
            ) ?? 0

            let mainOpen = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE planned_date = ? AND lane = 'main' AND done = 0",
                arguments: [today]
            ) ?? 0

            let tempOpen = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE planned_date = ? AND lane = 'temporary' AND done = 0",
                arguments: [today]
            ) ?? 0

            let nextTitle = try String.fetchOne(
                db,
                sql: """
                SELECT title FROM task
                WHERE planned_date = ? AND lane = 'main' AND done = 0
                ORDER BY sort_order LIMIT 1
                """,
                arguments: [today]
            )

            return WidgetSnapshot(
                pomodoros: pomodoros,
                focusMinutes: seconds / 60,
                mainTotal: mainTotal,
                mainOpen: mainOpen,
                tempOpen: tempOpen,
                nextTitle: nextTitle
            )
        }
    }
}
