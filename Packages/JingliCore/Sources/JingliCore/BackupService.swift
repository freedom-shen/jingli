import Foundation
import GRDB

public struct BackupInfo: Sendable, Identifiable {
    public let url: URL
    public let date: String
    public let bytes: Int

    public var id: String { url.path }
}

public struct ImportSummary: Sendable {
    public let projects: Int
    public let tasks: Int
}

/// 今日数据的 JSON 备份：项目 / 任务 / 今日计划；不导出历史番茄。
public final class BackupService: @unchecked Sendable {
    private let database: JingliDatabase
    private let backupDirectory: URL

    public init(database: JingliDatabase, backupDirectory: URL) {
        self.database = database
        self.backupDirectory = backupDirectory
    }

    @discardableResult
    public func exportJSON(now: Date = Date()) throws -> URL {
        let payload = try database.queue.read { db in
            try exportPayload(db, now: now)
        }
        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let url = backupDirectory
            .appendingPathComponent("jingli-\(formatter.string(from: now)).json")
        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 每天第一次调用生成一份备份；返回 nil 表示今天已有备份。
    @discardableResult
    public func dailyBackup(now: Date = Date(), keepDays: Int = 14) throws -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: now)
        let target = backupDirectory.appendingPathComponent("jingli-\(today).json")
        guard !FileManager.default.fileExists(atPath: target.path) else { return nil }

        let url = try exportJSON(now: now)
        try prune(keepDays: keepDays, now: now)
        return url
    }

    public func listBackups() throws -> [BackupInfo] {
        guard FileManager.default.fileExists(atPath: backupDirectory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        return urls
            .filter { $0.lastPathComponent.hasPrefix("jingli-") && $0.pathExtension == "json" }
            .compactMap { url in
                let name = url.deletingPathExtension().lastPathComponent
                let date = String(name.dropFirst("jingli-".count))
                let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return BackupInfo(url: url, date: date, bytes: bytes)
            }
            .sorted { $0.date > $1.date }
    }

    @discardableResult
    public func importJSON(from url: URL) throws -> ImportSummary {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackupError.invalidFormat
        }
        guard object["version"] as? Int == 1 else {
            throw BackupError.unsupportedVersion
        }
        let projects = object["projects"] as? [[String: Any]] ?? []
        let tasks = object["tasks"] as? [[String: Any]] ?? []

        try database.queue.write { db in
            for project in projects {
                guard let id = project["id"] as? String,
                      let name = project["name"] as? String else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO project (id, name, description, color, created_at, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        description = excluded.description,
                        color = excluded.color
                    """,
                    arguments: [
                        id,
                        name,
                        project["description"] as? String ?? "",
                        project["color"] as? String ?? "sage",
                        project["createdAt"] as? String ?? Self.timestamp(),
                        project["sortOrder"] as? Int ?? 0
                    ]
                )
            }

            for task in tasks {
                guard let id = task["id"] as? String,
                      let title = task["title"] as? String else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO task
                        (id, title, project_id, lane, planned_date, note, done,
                         created_at, completed_at, sort_order)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        project_id = excluded.project_id,
                        lane = excluded.lane,
                        planned_date = excluded.planned_date,
                        note = excluded.note,
                        done = excluded.done,
                        completed_at = excluded.completed_at
                    """,
                    arguments: [
                        id,
                        title,
                        task["projectId"] as? String,
                        task["lane"] as? String ?? "main",
                        task["plannedDate"] as? String,
                        task["note"] as? String ?? "",
                        task["done"] as? Bool ?? false,
                        task["createdAt"] as? String ?? Self.timestamp(),
                        task["completedAt"] as? String,
                        task["sortOrder"] as? Int ?? 0
                    ]
                )
            }
        }

        return ImportSummary(projects: projects.count, tasks: tasks.count)
    }

    private func exportPayload(_ db: Database, now: Date) throws -> [String: Any] {
        let projects = try Row.fetchAll(
            db,
            sql: "SELECT * FROM project ORDER BY sort_order, created_at"
        ).map { row -> [String: Any] in
            [
                "id": row["id"] as String,
                "name": row["name"] as String,
                "description": row["description"] as String,
                "color": row["color"] as String,
                "createdAt": row["created_at"] as String,
                "sortOrder": row["sort_order"] as Int
            ]
        }

        let tasks = try Row.fetchAll(
            db,
            sql: "SELECT * FROM task ORDER BY sort_order, created_at"
        ).map { row -> [String: Any] in
            var payload: [String: Any] = [
                "id": row["id"] as String,
                "title": row["title"] as String,
                "lane": row["lane"] as String,
                "note": row["note"] as String,
                "done": row["done"] as Bool,
                "createdAt": row["created_at"] as String,
                "sortOrder": row["sort_order"] as Int
            ]
            if let projectID: String = row["project_id"] { payload["projectId"] = projectID }
            if let planned: String = row["planned_date"] { payload["plannedDate"] = planned }
            if let completed: String = row["completed_at"] { payload["completedAt"] = completed }
            return payload
        }

        let today = DayKey.make()
        let plan = try Row.fetchOne(
            db,
            sql: "SELECT * FROM day_plan WHERE date = ?",
            arguments: [today]
        )
        var dayPlan: [String: Any] = ["date": today]
        if let plan {
            dayPlan["started"] = plan["started"] as Bool
            if let startedAt: String = plan["started_at"] {
                dayPlan["startedAt"] = startedAt
            }
        }
        let planTasks = try String.fetchAll(
            db,
            sql: "SELECT task_id FROM day_plan_task WHERE date = ?",
            arguments: [today]
        )
        dayPlan["taskIds"] = planTasks

        return [
            "version": 1,
            "exportedAt": ISO8601DateFormatter().string(from: now),
            "projects": projects,
            "tasks": tasks,
            "dayPlan": dayPlan
        ]
    }

    private func prune(keepDays: Int, now: Date) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keepDays, to: now) else {
            return
        }
        let cutoffText = formatter.string(from: cutoff)
        for info in try listBackups() where info.date < cutoffText {
            try? FileManager.default.removeItem(at: info.url)
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

public enum BackupError: Error, LocalizedError {
    case invalidFormat
    case unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "备份文件格式不正确"
        case .unsupportedVersion: return "备份文件版本不支持"
        }
    }
}
