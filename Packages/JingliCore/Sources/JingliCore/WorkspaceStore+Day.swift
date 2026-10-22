import Foundation
import GRDB

public struct DayStartGroup: Sendable, Identifiable {
    public let id: String
    public let project: Project?
    public let tasks: [Task]
}

public struct TodaySnapshot: Sendable {
    public let projects: [Project]
    public let todayTasks: [Task]
    public let groups: [DayStartGroup]
    public let dayStarted: Bool
    public let selection: [String]
}

public enum DayPlanError: Error, LocalizedError {
    case emptySelection
    case taskNotFound
    case taskCompleted
    case tooManyMainTasks(Int)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "至少选择一件任务"
        case .taskNotFound:
            return "任务已不存在"
        case .taskCompleted:
            return "已完成的任务不能加入今日计划"
        case let .tooManyMainTasks(count):
            return "主线任务最多 4 个，当前会变成 \(count) 个"
        }
    }
}

public extension WorkspaceStore {
    func listProjects() throws -> [Project] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM project ORDER BY sort_order, created_at"
            ).map(Project.init(row:))
        }
    }

    func listTasks(includeDone: Bool = false) throws -> [Task] {
        try database.queue.read { db in
            let condition = includeDone ? "" : " WHERE done = 0"
            return try Row.fetchAll(
                db,
                sql: "SELECT * FROM task\(condition) ORDER BY sort_order, created_at"
            ).map(Task.init(row:))
        }
    }

    func todayTasks(today: String = DayKey.make()) throws -> [Task] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM task
                WHERE planned_date = ?
                ORDER BY lane = 'temporary', sort_order, created_at
                """,
                arguments: [today]
            ).map(Task.init(row:))
        }
    }

    func dayStartGroups() throws -> [DayStartGroup] {
        let projects = try listProjects()
        let tasks = try listTasks(includeDone: false)
        let grouped = Dictionary(grouping: tasks) { $0.projectID ?? "" }

        var groups = projects.compactMap { project -> DayStartGroup? in
            let items = grouped[project.id] ?? []
            guard !items.isEmpty else { return nil }
            return DayStartGroup(id: project.id, project: project, tasks: items)
        }
        if let uncategorized = grouped[""], !uncategorized.isEmpty {
            groups.append(
                DayStartGroup(id: "uncategorized", project: nil, tasks: uncategorized)
            )
        }
        return groups
    }

    func snapshot(today: String = DayKey.make()) throws -> TodaySnapshot {
        let projects = try listProjects()
        let groups = try dayStartGroups()
        let todayTasks = try todayTasks(today: today)

        let plan = try database.queue.read { db -> (Bool, [String]) in
            let started = try Bool.fetchOne(
                db,
                sql: "SELECT started FROM day_plan WHERE date = ?",
                arguments: [today]
            ) ?? false
            if started {
                return (true, todayTasks.map(\.id))
            }
            let ids = try String.fetchAll(
                db,
                sql: "SELECT task_id FROM day_plan_task WHERE date = ? ORDER BY selected_at",
                arguments: [today]
            )
            return (false, ids)
        }

        return TodaySnapshot(
            projects: projects,
            todayTasks: todayTasks,
            groups: groups,
            dayStarted: plan.0,
            selection: plan.1
        )
    }

    func saveDaySelection(
        taskIDs: [String],
        today: String = DayKey.make()
    ) throws {
        let tasks = try validateSelection(taskIDs, today: today, checkCompletedSlots: false)
        let unique = tasks.map(\.id)

        try database.queue.write { db in
            try db.execute(
                sql: "DELETE FROM day_plan_task WHERE date = ?",
                arguments: [today]
            )
            let now = Self.timestamp()
            for task in tasks {
                try db.execute(
                    sql: """
                    INSERT INTO day_plan_task (date, task_id, lane, selected_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [today, task.id, task.lane, now]
                )
            }
            try db.execute(
                sql: """
                INSERT INTO day_plan (date, started, started_at)
                VALUES (?, 0, NULL)
                ON CONFLICT(date) DO UPDATE SET started = 0, started_at = NULL
                """,
                arguments: [today]
            )
            _ = unique
        }
    }

    func startDay(
        taskIDs: [String],
        today: String = DayKey.make()
    ) throws {
        let tasks = try validateSelection(taskIDs, today: today, checkCompletedSlots: true)
        let unique = tasks.map(\.id)
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ",")

        try database.queue.write { db in
            try db.execute(
                sql: """
                UPDATE task SET planned_date = NULL
                WHERE planned_date = ? AND id NOT IN (\(placeholders))
                """,
                arguments: StatementArguments([today] + unique)
            )
            try db.execute(
                sql: "UPDATE task SET planned_date = ? WHERE id IN (\(placeholders))",
                arguments: StatementArguments([today] + unique)
            )

            try db.execute(
                sql: "DELETE FROM day_plan_task WHERE date = ?",
                arguments: [today]
            )
            let now = Self.timestamp()
            for task in tasks {
                try db.execute(
                    sql: """
                    INSERT INTO day_plan_task (date, task_id, lane, selected_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [today, task.id, task.lane, now]
                )
            }
            try db.execute(
                sql: """
                INSERT INTO day_plan (date, started, started_at)
                VALUES (?, 1, ?)
                ON CONFLICT(date) DO UPDATE SET started = 1, started_at = excluded.started_at
                """,
                arguments: [today, now]
            )
        }
    }

    func resetDay(today: String = DayKey.make()) throws {
        try database.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET planned_date = NULL WHERE planned_date = ?",
                arguments: [today]
            )
            try db.execute(
                sql: "DELETE FROM day_plan_task WHERE date = ?",
                arguments: [today]
            )
            try db.execute(
                sql: "DELETE FROM day_plan WHERE date = ?",
                arguments: [today]
            )
        }
    }

    @discardableResult
    func toggleTask(id: String) throws -> Task? {
        try database.queue.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM task WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }

            let done = current["done"] as Bool
            let nextDone = !done
            let completedAt = nextDone
                ? ISO8601DateFormatter().string(from: Date())
                : nil

            try db.execute(
                sql: "UPDATE task SET done = ?, completed_at = ? WHERE id = ?",
                arguments: [nextDone, completedAt, id]
            )

            guard let updated = try Row.fetchOne(
                db,
                sql: "SELECT * FROM task WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }
            return Task(row: updated)
        }
    }

    private func validateSelection(
        _ taskIDs: [String],
        today: String,
        checkCompletedSlots: Bool
    ) throws -> [Task] {
        var seen = Set<String>()
        let unique = taskIDs.filter { id in
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
        guard !unique.isEmpty else { throw DayPlanError.emptySelection }

        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ",")
        let tasks = try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM task WHERE id IN (\(placeholders))",
                arguments: StatementArguments(unique)
            ).map(Task.init(row:))
        }
        guard tasks.count == unique.count else { throw DayPlanError.taskNotFound }
        guard tasks.allSatisfy({ !$0.done }) else { throw DayPlanError.taskCompleted }

        let mainCount = tasks.filter { $0.lane == "main" }.count
        guard mainCount <= 4 else { throw DayPlanError.tooManyMainTasks(mainCount) }

        if checkCompletedSlots {
            let completedMain = try database.queue.read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                    SELECT COUNT(*) FROM task
                    WHERE planned_date = ? AND done = 1 AND lane = 'main'
                      AND id NOT IN (\(placeholders))
                    """,
                    arguments: StatementArguments([today] + unique)
                ) ?? 0
            }
            guard completedMain + mainCount <= 4 else {
                throw DayPlanError.tooManyMainTasks(completedMain + mainCount)
            }
        }

        return tasks
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

extension Project {
    init(row: Row) {
        self.init(
            id: row["id"],
            name: row["name"],
            description: row["description"],
            color: row["color"],
            createdAt: row["created_at"],
            sortOrder: row["sort_order"]
        )
    }
}

extension Task {
    init(row: Row) {
        self.init(
            id: row["id"],
            title: row["title"],
            projectID: row["project_id"],
            lane: row["lane"],
            plannedDate: row["planned_date"],
            note: row["note"],
            done: row["done"],
            createdAt: row["created_at"],
            completedAt: row["completed_at"],
            sortOrder: row["sort_order"]
        )
    }
}
