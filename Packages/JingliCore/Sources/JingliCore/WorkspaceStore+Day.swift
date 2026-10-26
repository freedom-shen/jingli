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
    case mainTaskLocked

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
        case .mainTaskLocked:
            return "今天已经开始，主线任务只能在项目里维护；今天要加任务请用临时任务"
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
                sql: "SELECT * FROM task\(condition) ORDER BY created_at DESC, sort_order DESC"
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
                ORDER BY lane = 'temporary', created_at DESC, sort_order DESC
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
        let tasks = taskIDs.isEmpty
            ? []
            : try validateSelection(taskIDs, today: today, checkCompletedSlots: false)
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

    /// 把已有任务追加进今天：不复制任务、不改 lane 和项目归属，只挂到今日计划。
    /// 主线任务占用今天的 4 个空位（含已完成的），满了会抛 tooManyMainTasks。
    @discardableResult
    func addToToday(
        taskIDs: [String],
        today: String = DayKey.make()
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

        let fresh = tasks.filter { $0.plannedDate != today }
        let newMain = fresh.filter { $0.lane == "main" }.count
        if newMain > 0 {
            let usedMain = try plannedMainCount(today: today)
            guard usedMain + newMain <= 4 else {
                throw DayPlanError.tooManyMainTasks(usedMain + newMain)
            }
        }
        guard !fresh.isEmpty else { return [] }

        let now = Self.timestamp()
        try database.queue.write { db in
            for task in fresh {
                try db.execute(
                    sql: "UPDATE task SET planned_date = ? WHERE id = ?",
                    arguments: [today, task.id]
                )
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
                ON CONFLICT(date) DO NOTHING
                """,
                arguments: [today]
            )
        }
        return fresh
    }

    /// 今天已占用多少个主线名额（含未开工时勾选的和已完成的）。
    func plannedMainCount(today: String = DayKey.make()) throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*) FROM task t
                JOIN day_plan_task d ON d.task_id = t.id AND d.date = ?
                WHERE t.lane = 'main'
                """,
                arguments: [today]
            ) ?? 0
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
    func updateProject(
        id: String,
        name: String,
        description: String,
        color: String
    ) throws -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        let normalizedColor = ["sage", "amber", "blue", "rose", "violet", "slate"].contains(color)
            ? color : "sage"

        return try database.queue.write { db in
            try db.execute(
                sql: "UPDATE project SET name = ?, description = ?, color = ? WHERE id = ?",
                arguments: [String(trimmed.prefix(60)), String(description.prefix(500)), normalizedColor, id]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM project WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            return Project(row: row)
        }
    }

    func deleteProject(id: String) throws {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM project WHERE id = ?", arguments: [id])
        }
    }

    func tasks(projectID: String) throws -> [Task] {
        try database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM task
                WHERE project_id = ?
                ORDER BY done, created_at DESC, sort_order DESC
                """,
                arguments: [projectID]
            ).map(Task.init(row:))
        }
    }

    /// 今日已计入这件任务的番茄数（按分摊份额累加）。
    func creditTotals(today: String = DayKey.make()) throws -> [String: Double] {
        try database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT fst.task_id AS task_id, SUM(fst.share) AS total
                FROM focus_session_task fst
                JOIN focus_session fs ON fs.id = fst.session_id
                WHERE fs.session_date = ? AND fs.status = 'completed'
                GROUP BY fst.task_id
                """,
                arguments: [today]
            )
            var result: [String: Double] = [:]
            for row in rows {
                result[row["task_id"]] = row["total"]
            }
            return result
        }
    }

    func creditTotal(taskID: String, today: String = DayKey.make()) throws -> Double {
        try database.queue.read { db in
            try Double.fetchOne(
                db,
                sql: """
                SELECT COALESCE(SUM(fst.share), 0)
                FROM focus_session_task fst
                JOIN focus_session fs ON fs.id = fst.session_id
                WHERE fst.task_id = ? AND fs.session_date = ? AND fs.status = 'completed'
                """,
                arguments: [taskID, today]
            ) ?? 0
        }
    }

    func validateDaySelection(
        taskIDs: [String],
        today: String = DayKey.make()
    ) throws -> [Task] {
        try validateSelection(taskIDs, today: today, checkCompletedSlots: true)
    }

    @discardableResult
    func deleteTask(id: String) throws -> Bool {
        try database.queue.write { db in
            try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
            return db.changesCount > 0
        }
    }

    @discardableResult
    func updateTask(
        id: String,
        title: String,
        note: String,
        estimate: Int?
    ) throws -> Task? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        let normalizedEstimate = estimate.map { max(1, min(32, $0)) }

        return try database.queue.write { db in
            try db.execute(
                sql: "UPDATE task SET title = ?, note = ?, estimate = ? WHERE id = ?",
                arguments: [
                    String(trimmed.prefix(160)),
                    String(note.prefix(8000)),
                    normalizedEstimate,
                    id
                ]
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

            if nextDone, let completedAt {
                try db.execute(
                    sql: """
                    INSERT INTO task_completion (id, task_id, completed_at)
                    VALUES (?, ?, ?)
                    """,
                    arguments: [UUID().uuidString, id, completedAt]
                )
            } else {
                try db.execute(
                    sql: """
                    DELETE FROM task_completion
                    WHERE id = (
                        SELECT id FROM task_completion
                        WHERE task_id = ?
                        ORDER BY completed_at DESC, rowid DESC
                        LIMIT 1
                    )
                    """,
                    arguments: [id]
                )
            }

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

    func settingValue(_ key: String) throws -> String? {
        try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM setting WHERE key = ?",
                arguments: [key]
            )
        }
    }

    func setSettingValue(_ key: String, _ value: String?) throws {
        try database.queue.write { db in
            if let value {
                try db.execute(
                    sql: """
                    INSERT INTO setting (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [key, value]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM setting WHERE key = ?",
                    arguments: [key]
                )
            }
        }
    }

    /// 每天第一次使用（启动或跨零点）时清掉昨日痕迹，返回是否执行了跨天。
    @discardableResult
    func rolloverIfNeeded(today: String = DayKey.make()) throws -> Bool {
        let lastSeen = try database.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM setting WHERE key = ?",
                arguments: ["last_seen_day"]
            )
        }
        guard lastSeen != today else { return false }

        try database.rollover(to: today)
        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO setting (key, value) VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
                arguments: ["last_seen_day", today]
            )
        }
        return true
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
            sortOrder: row["sort_order"],
            estimate: row["estimate"]
        )
    }
}
