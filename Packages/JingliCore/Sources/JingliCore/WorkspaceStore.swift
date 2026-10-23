import Foundation
import GRDB

public struct Project: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let color: String
    public let createdAt: String
    public let sortOrder: Int
}

public struct Task: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let projectID: String?
    public let lane: String
    public let plannedDate: String?
    public let note: String
    public let done: Bool
    public let createdAt: String
    public let completedAt: String?
    public let sortOrder: Int
}

public final class WorkspaceStore: @unchecked Sendable {
    public let database: JingliDatabase

    public init(database: JingliDatabase) {
        self.database = database
    }

    @discardableResult
    public func createProject(
        name: String,
        description: String = "",
        color: String = "sage"
    ) throws -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        let normalizedColor = ["sage", "amber", "blue", "rose", "violet", "slate"].contains(color)
            ? color : "sage"
        let project = Project(
            id: UUID().uuidString,
            name: String(trimmed.prefix(60)),
            description: String(description.prefix(500)),
            color: normalizedColor,
            createdAt: Self.timestamp(),
            sortOrder: try nextSortOrder(table: "project")
        )
        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO project (id, name, description, color, created_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    project.id, project.name, project.description,
                    project.color, project.createdAt, project.sortOrder
                ]
            )
        }
        return project
    }

    @discardableResult
    public func createTask(
        title: String,
        projectID: String? = nil,
        lane: String = "main",
        plannedDate: String? = nil
    ) throws -> Task {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.emptyTitle }
        let normalizedLane = lane == "temporary" ? "temporary" : "main"
        if normalizedLane == "main", let plannedDate,
           try isDayStarted(plannedDate) {
            throw DayPlanError.mainTaskLocked
        }
        let task = Task(
            id: UUID().uuidString,
            title: String(trimmed.prefix(160)),
            projectID: projectID,
            lane: normalizedLane,
            plannedDate: plannedDate,
            note: "",
            done: false,
            createdAt: Self.timestamp(),
            completedAt: nil,
            sortOrder: try nextSortOrder(table: "task")
        )
        try database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO task
                (id, title, project_id, lane, planned_date, note, done, created_at, completed_at, sort_order)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    task.id, task.title, task.projectID, task.lane,
                    task.plannedDate, task.note, task.done, task.createdAt,
                    task.completedAt, task.sortOrder
                ]
            )
        }
        return task
    }

    public func taskCount() throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task") ?? 0
        }
    }

    private func isDayStarted(_ date: String) throws -> Bool {
        try database.queue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT started FROM day_plan WHERE date = ?",
                arguments: [date]
            ) ?? false
        }
    }

    private func nextSortOrder(table: String) throws -> Int {
        try database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM \(table)") ?? 0
        }
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

public enum StoreError: Error, LocalizedError {
    case emptyTitle

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: return "title must not be empty"
        }
    }
}
