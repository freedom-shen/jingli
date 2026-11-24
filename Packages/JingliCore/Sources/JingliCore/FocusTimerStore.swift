import Foundation
import GRDB

public struct FocusCompletion: Sendable, Identifiable {
    public let sessionID: String
    public let taskIDs: [String]
    public let shares: [String: Double]

    public var id: String { sessionID }

    public init(sessionID: String, taskIDs: [String], shares: [String: Double]) {
        self.sessionID = sessionID
        self.taskIDs = taskIDs
        self.shares = shares
    }
}

public final class FocusTimerStore: @unchecked Sendable {
    private let database: JingliDatabase
    private let activeKey = "active_timer"

    public init(database: JingliDatabase) {
        self.database = database
    }

    public func saveActive(_ timer: FocusTimer?) throws {
        let now = Date()
        try database.queue.write { db in
            // 换 session / 结束时要把「上一轮」的远端可见状态收尾，先把它读出来。
            let previousSessionID = try Self.storedSessionID(db: db, key: activeKey)

            guard let timer,
                  let data = try? JSONEncoder().encode(timer),
                  let json = String(data: data, encoding: .utf8) else {
                try db.execute(
                    sql: "DELETE FROM setting WHERE key = ?",
                    arguments: [activeKey]
                )
                try Self.mirrorAbort(db: db, sessionID: previousSessionID, now: now)
                return
            }
            try db.execute(
                sql: """
                INSERT INTO setting (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: [activeKey, json]
            )

            if timer.isActive, let sessionID = timer.sessionID {
                if let previousSessionID, previousSessionID != sessionID {
                    // 上一轮是崩溃留下的（本地已经换了新 session），别让它永远挂在对面
                    try Self.mirrorAbort(db: db, sessionID: previousSessionID, now: now)
                }
                try Self.mirrorActive(db: db, timer: timer, sessionID: sessionID)
            } else if let sessionID = timer.sessionID {
                try Self.mirrorAbort(db: db, sessionID: sessionID, now: now)
            }
        }
    }

    // MARK: - 把「正在进行」写进 focus_session，给另一台设备看

    /// 计时器本身是设备本地状态（`setting.active_timer` 不参与同步），另一台设备没法知道
    /// 你在专注什么。所以开始 / 暂停 / 恢复时，把这一轮镜像进 `focus_session`
    /// （`status = running / paused`），对面拉下来就能显示「Mac 上正在专注 · 任务名 · 剩 N 分钟」。
    ///
    /// 统计口径不受影响：今日番茄、历史、小组件全部只读 `status = 'completed'`。
    /// `ended_at` 在未完成时先写「预计结束时间」，完成时再被 `complete()` 覆盖成实际结束时间。
    private static func mirrorActive(
        db: Database,
        timer: FocusTimer,
        sessionID: String
    ) throws {
        let formatter = ISO8601DateFormatter()
        let startedAt = timer.startedAt.map {
            formatter.string(from: Date(timeIntervalSince1970: Double($0) / 1000))
        } ?? formatter.string(from: Date())
        let expectedEnd = timer.endsAt.map {
            formatter.string(from: Date(timeIntervalSince1970: Double($0) / 1000))
        }
        let status = timer.phase == .paused ? "paused" : "running"

        try db.execute(
            sql: """
            INSERT INTO focus_session
            (id, session_date, started_at, ended_at, duration_sec, status,
             credited, focus_mode_on, focus_mode_owned)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                session_date = excluded.session_date,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                duration_sec = excluded.duration_sec,
                status = excluded.status,
                credited = 0,
                focus_mode_on = excluded.focus_mode_on,
                focus_mode_owned = excluded.focus_mode_owned
            """,
            arguments: [
                sessionID, timer.sessionDate, startedAt, expectedEnd,
                timer.durationMs / 1000, status,
                timer.focusModeOn, timer.focusModeOwned
            ]
        )

        // 中途可能加减任务，整组重建（表很小，且只在开始/暂停/恢复时发生）
        try db.execute(
            sql: "DELETE FROM focus_session_task WHERE session_id = ?",
            arguments: [sessionID]
        )
        let shares = FocusCredit.shares(participants: timer.taskIDs.count)
        for (taskID, share) in zip(timer.taskIDs, shares) {
            try db.execute(
                sql: """
                INSERT INTO focus_session_task (session_id, task_id, share)
                VALUES (?, ?, ?)
                """,
                arguments: [sessionID, taskID, share]
            )
        }
    }

    /// 放弃 / 结束但没有正常完成：把远端可见的那行收成 aborted（不计入任何统计）。
    private static func mirrorAbort(db: Database, sessionID: String?, now: Date) throws {
        guard let sessionID else { return }
        let formatter = ISO8601DateFormatter()
        try db.execute(
            sql: """
            UPDATE focus_session
            SET status = 'aborted', ended_at = ?
            WHERE id = ? AND status IN ('running', 'paused')
            """,
            arguments: [formatter.string(from: now), sessionID]
        )
    }

    private static func storedSessionID(db: Database, key: String) throws -> String? {
        guard let json = try String.fetchOne(
            db,
            sql: "SELECT value FROM setting WHERE key = ?",
            arguments: [key]
        ), let data = json.data(using: .utf8),
           let timer = try? JSONDecoder().decode(FocusTimer.self, from: data) else {
            return nil
        }
        return timer.sessionID
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
                INSERT INTO focus_session
                (id, session_date, started_at, ended_at, duration_sec, status,
                 credited, focus_mode_on, focus_mode_owned)
                VALUES (?, ?, ?, ?, ?, 'completed', 1, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    session_date = excluded.session_date,
                    started_at = excluded.started_at,
                    ended_at = excluded.ended_at,
                    duration_sec = excluded.duration_sec,
                    status = excluded.status,
                    credited = excluded.credited,
                    focus_mode_on = excluded.focus_mode_on,
                    focus_mode_owned = excluded.focus_mode_owned
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
