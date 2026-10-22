import Foundation
import GRDB

public struct FocusRecordTask: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let share: Double

    public init(id: String, title: String, share: Double) {
        self.id = id
        self.title = title
        self.share = share
    }
}

public struct FocusRecord: Sendable, Identifiable {
    public let id: String
    public let startedAt: String
    public let durationSec: Int
    public let tasks: [FocusRecordTask]

    public init(id: String, startedAt: String, durationSec: Int, tasks: [FocusRecordTask]) {
        self.id = id
        self.startedAt = startedAt
        self.durationSec = durationSec
        self.tasks = tasks
    }
}

public struct TodayStats: Sendable {
    public let pomodoros: Int
    public let focusSeconds: Int
    public let completedTasks: Int
    public let records: [FocusRecord]

    public init(pomodoros: Int, focusSeconds: Int, completedTasks: Int, records: [FocusRecord]) {
        self.pomodoros = pomodoros
        self.focusSeconds = focusSeconds
        self.completedTasks = completedTasks
        self.records = records
    }
}

public extension WorkspaceStore {
    func todayStats(today: String = DayKey.make()) throws -> TodayStats {
        try database.queue.read { db in
            let sessions = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM focus_session
                WHERE session_date = ? AND status = 'completed'
                ORDER BY started_at DESC
                """,
                arguments: [today]
            )

            var records: [FocusRecord] = []
            var totalSeconds = 0

            for session in sessions {
                let sessionID: String = session["id"]
                totalSeconds += session["duration_sec"] as Int
                let taskRows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT t.id, t.title, fst.share
                    FROM focus_session_task fst
                    JOIN task t ON t.id = fst.task_id
                    WHERE fst.session_id = ?
                    ORDER BY t.sort_order, t.created_at
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
                records.append(
                    FocusRecord(
                        id: sessionID,
                        startedAt: session["started_at"],
                        durationSec: session["duration_sec"],
                        tasks: tasks
                    )
                )
            }

            let completedTasks = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE planned_date = ? AND done = 1",
                arguments: [today]
            ) ?? 0

            return TodayStats(
                pomodoros: records.count,
                focusSeconds: totalSeconds,
                completedTasks: completedTasks,
                records: records
            )
        }
    }
}
