import Foundation
import GRDB

/// 另一台设备正在进行的一轮番茄钟（只读展示用）。
///
/// 计时器本身是本机状态（`setting.active_timer` 不参与同步）。为了知道「对面在专注什么」，
/// 计时器开始 / 暂停 / 恢复时会把这一轮镜像进 `focus_session`（`status = running / paused`），
/// 这条记录会随普通变更同步过来。这里只负责把它读出来给界面显示，不做任何控制。
public struct RemoteFocusSession: Sendable, Equatable {
    public let sessionID: String
    public let taskTitles: [String]
    public let startedAt: Date?
    /// 预计结束时间；暂停时为 nil。
    public let endsAt: Date?
    public let isPaused: Bool
    public let durationSeconds: Int

    public init(
        sessionID: String,
        taskTitles: [String],
        startedAt: Date?,
        endsAt: Date?,
        isPaused: Bool,
        durationSeconds: Int
    ) {
        self.sessionID = sessionID
        self.taskTitles = taskTitles
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.isPaused = isPaused
        self.durationSeconds = durationSeconds
    }

    public func remainingMs(now: Date = Date()) -> Int {
        guard !isPaused, let endsAt else { return 0 }
        return max(0, Int(endsAt.timeIntervalSince(now) * 1000))
    }

    /// 「剩 12 分钟」/「已暂停」
    /// 用分钟粒度：另一台设备的界面不会每秒重绘，显示秒数反而会停住不动。
    public func remainingText(now: Date = Date()) -> String {
        guard !isPaused else { return "已暂停" }
        let minutes = max(1, Int(ceil(Double(remainingMs(now: now)) / 60_000)))
        return "剩 \(minutes) 分钟"
    }

    ///「帮助中心的上线准备 + 自定义组件的调试查看」
    public var titleText: String {
        taskTitles.isEmpty ? "未命名任务" : taskTitles.joined(separator: " + ")
    }
}

public extension WorkspaceStore {
    /// 找另一台设备正在进行的那一轮。
    ///
    /// - `excluding`: 本机自己的 session（本机有计时器时排除，避免把自己显示成「对面」）。
    /// - 超过预计结束 `staleGrace` 还没收尾的（对面崩溃 / 卸载）当作不存在。
    func remoteFocusSession(
        today: String = DayKey.make(),
        excluding sessionID: String? = nil,
        now: Date = Date(),
        staleGrace: TimeInterval = 15 * 60
    ) throws -> RemoteFocusSession? {
        try database.queue.read { db in
            var sql = """
                SELECT * FROM focus_session
                WHERE session_date = ? AND status IN ('running', 'paused')
                """
            var values: [any DatabaseValueConvertible?] = [today]
            if let sessionID {
                sql += " AND id <> ?"
                values.append(sessionID)
            }
            sql += " ORDER BY started_at DESC LIMIT 5"

            let formatter = ISO8601DateFormatter()
            for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(values)) {
                let status: String = row["status"]
                let isPaused = status == "paused"
                let startedAt = (row["started_at"] as String?).flatMap(formatter.date(from:))
                let expectedEnd = (row["ended_at"] as String?).flatMap(formatter.date(from:))
                let durationSeconds: Int = row["duration_sec"] ?? 0
                let endsAt = expectedEnd ?? startedAt.map {
                    $0.addingTimeInterval(TimeInterval(durationSeconds))
                }
                // 对面异常退出：过了预计结束还挂着 running 的，当作已经结束
                if !isPaused, let endsAt, endsAt.addingTimeInterval(staleGrace) < now {
                    continue
                }
                if !isPaused, endsAt == nil {
                    continue
                }

                let sessionID: String = row["id"]
                let titles = try String.fetchAll(
                    db,
                    sql: """
                        SELECT t.title FROM focus_session_task fst
                        JOIN task t ON t.id = fst.task_id
                        WHERE fst.session_id = ?
                        ORDER BY t.created_at
                        """,
                    arguments: [sessionID]
                )
                return RemoteFocusSession(
                    sessionID: sessionID,
                    taskTitles: titles,
                    startedAt: startedAt,
                    endsAt: isPaused ? nil : endsAt,
                    isPaused: isPaused,
                    durationSeconds: durationSeconds
                )
            }
            return nil
        }
    }
}
