import Foundation
import GRDB

public struct HistoryTask: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let projectID: String?
    public let completedAt: String

    public init(id: String, title: String, projectID: String?, completedAt: String) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.completedAt = completedAt
    }
}

public struct DayHistory: Sendable, Identifiable {
    public let date: String
    public let pomodoros: Int
    public let focusSeconds: Int
    public let completedTasks: [HistoryTask]
    public let records: [FocusRecord]

    public var id: String { date }

    public init(
        date: String,
        pomodoros: Int,
        focusSeconds: Int,
        completedTasks: [HistoryTask],
        records: [FocusRecord]
    ) {
        self.date = date
        self.pomodoros = pomodoros
        self.focusSeconds = focusSeconds
        self.completedTasks = completedTasks
        self.records = records
    }
}

public enum HistoryError: Error, LocalizedError {
    case invalidDate(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDate(value):
            return "日期格式不正确：\(value)，应为 yyyy-MM-dd"
        }
    }
}

public extension WorkspaceStore {
    /// 最近 N 天的回顾，包含每天完成的番茄、专注时长、完成的任务和当天记录。
    /// 返回按日期倒序（今天在前）。
    func history(days: Int = 7, endingOn: String = DayKey.make()) throws -> [DayHistory] {
        let count = max(1, min(days, 3650))
        let keys = try historyDateKeys(endingOn: endingOn, days: count)
        guard let start = keys.last, let end = keys.first else { return [] }
        let dateSet = Set(keys)

        let recordsByDate: [String: [FocusRecord]] = try database.queue.read { db in
            let sessions = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM focus_session
                WHERE status = 'completed' AND session_date BETWEEN ? AND ?
                ORDER BY session_date DESC, started_at DESC
                """,
                arguments: [start, end]
            )

            var map: [String: [FocusRecord]] = [:]
            for session in sessions {
                let sessionID: String = session["id"]
                let sessionDate: String = session["session_date"]
                let taskRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT t.id, t.title, fst.share
                    FROM focus_session_task fst
                    JOIN task t ON t.id = fst.task_id
                    WHERE fst.session_id = ?
                    ORDER BY t.created_at DESC, t.sort_order DESC
                    """,
                    arguments: [sessionID]
                )
                let tasks = taskRows.map {
                    FocusRecordTask(
                        id: $0["id"],
                        title: $0["title"],
                        share: $0["share"]
                    )
                }
                map[sessionDate, default: []].append(
                    FocusRecord(
                        id: sessionID,
                        startedAt: session["started_at"],
                        durationSec: session["duration_sec"],
                        tasks: tasks
                    )
                )
            }
            return map
        }

        let completedByDate: [String: [HistoryTask]] = try database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT tc.task_id, tc.completed_at, t.title, t.project_id
                FROM task_completion tc
                JOIN task t ON t.id = tc.task_id
                ORDER BY tc.completed_at DESC
                """
            )

            let iso = ISO8601DateFormatter()
            let isoFractional = ISO8601DateFormatter()
            isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var map: [String: [HistoryTask]] = [:]
            for row in rows {
                let completedAt: String = row["completed_at"]
                guard let date = iso.date(from: completedAt)
                    ?? isoFractional.date(from: completedAt) else {
                    continue
                }
                let key = DayKey.make(from: date)
                guard dateSet.contains(key) else { continue }
                map[key, default: []].append(
                    HistoryTask(
                        id: row["task_id"],
                        title: row["title"],
                        projectID: row["project_id"],
                        completedAt: completedAt
                    )
                )
            }
            return map
        }

        return keys.map { key in
            let records = recordsByDate[key] ?? []
            return DayHistory(
                date: key,
                pomodoros: records.count,
                focusSeconds: records.reduce(0) { $0 + $1.durationSec },
                completedTasks: completedByDate[key] ?? [],
                records: records
            )
        }
    }

    private func historyDateKeys(endingOn: String, days: Int) throws -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard endingOn.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let end = formatter.date(from: endingOn),
              formatter.string(from: end) == endingOn else {
            throw HistoryError.invalidDate(endingOn)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else {
                return nil
            }
            return formatter.string(from: date)
        }
    }
}
