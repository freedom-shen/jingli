import Foundation
import GRDB

public struct FocusCompletion: Sendable, Identifiable {
    public let sessionID: String
    public let taskIDs: [String]
    public let shares: [String: Double]

    public var id: String { sessionID }
}

public final class FocusTimerStore: @unchecked Sendable {
    private let database: JingliDatabase
    private let activeKey = "active_timer"

    public init(database: JingliDatabase) {
        self.database = database
    }

    public func saveActive(_ timer: FocusTimer?) throws {
        try database.queue.write { db in
            guard let timer,
                  let data = try? JSONEncoder().encode(timer),
                  let json = String(data: data, encoding: .utf8) else {
                try db.execute(
                    sql: "DELETE FROM setting WHERE key = ?",
                    arguments: [activeKey]
                )
                return
            }
            try db.execute(
                sql: """
                INSERT INTO setting (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [activeKey, json]
            )
        }
    }

    public func loadActive(today: String = DayKey.make()) throws -> FocusTimer? {
        try database.queue.read { db in
            guard let json = try String.fetchOne(
                db,
                sql: "SELECT value FROM setting WHERE key = ?",
                arguments: [activeKey]
            ), let data = json.data(using: .utf8),
               let timer = try? JSONDecoder().decode(FocusTimer.self, from: data) else {
                return nil
            }
            guard timer.sessionDate == today, timer.isActive else { return nil }
            return timer
        }
    }

    public func clearActive() throws {
        try saveActive(nil)
    }

    @discardableResult
    public func complete(_ timer: FocusTimer, now: Date = Date()) throws -> FocusCompletion? {
        guard timer.phase == .finished, let sessionID = timer.sessionID else {
            return nil
        }

        let shares = FocusCredit.shares(participants: timer.taskIDs.count)
        let shareMap = Dictionary(uniqueKeysWithValues: zip(timer.taskIDs, shares))
        let formatter = ISO8601DateFormatter()
        let startedAt = timer.startedAt.map {
            formatter.string(from: Date(timeIntervalSince1970: Double($0) / 1000))
        } ?? formatter.string(from: now)
        let endedAt = formatter.string(from: now)

        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO focus_session
                (id, session_date, started_at, ended_at, duration_sec, status,
                 credited, focus_mode_on, focus_mode_owned)
                VALUES (?, ?, ?, ?, ?, 'completed', 1, ?, ?)
                """,
                arguments: [
                    sessionID, timer.sessionDate, startedAt, endedAt,
                    timer.durationMs / 1000, timer.focusModeOn, timer.focusModeOwned
                ]
            )
            try db.execute(
                sql: "DELETE FROM focus_session_task WHERE session_id = ?",
                arguments: [sessionID]
            )
            for (taskID, share) in shareMap {
                try db.execute(
                    sql: """
                    INSERT INTO focus_session_task (session_id, task_id, share)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [sessionID, taskID, share]
                )
            }
            try db.execute(
                sql: "DELETE FROM setting WHERE key = ?",
                arguments: [activeKey]
            )
        }

        return FocusCompletion(
            sessionID: sessionID,
            taskIDs: timer.taskIDs,
            shares: shareMap
        )
    }
}
