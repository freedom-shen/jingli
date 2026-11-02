import XCTest
@testable import JingliCore

final class WorkspaceProjectTests: XCTestCase {
    func testUpdateProject() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")

        let updated = try store.updateProject(
            id: project.id,
            name: "深度工作",
            description: "重要但不紧急",
            color: "blue"
        )

        XCTAssertEqual(updated?.name, "深度工作")
        XCTAssertEqual(updated?.description, "重要但不紧急")
        XCTAssertEqual(updated?.color, "blue")
    }

    func testDeleteProjectKeepsTasks() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        _ = try store.createTask(title: "任务", projectID: project.id)

        try store.deleteProject(id: project.id)

        XCTAssertTrue(try store.listProjects().isEmpty)
        XCTAssertNil(try store.tasks(projectID: project.id).first)
        let all = try store.listTasks(includeDone: true)
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all.first?.projectID)
    }

    func testTasksForProject() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        _ = try store.createTask(title: "A", projectID: project.id)
        _ = try store.createTask(title: "B", projectID: project.id)
        _ = try store.createTask(title: "C", projectID: nil)

        XCTAssertEqual(try store.tasks(projectID: project.id).count, 2)
    }
}

extension WorkspaceProjectTests {
    func testCompletedTasksAreOrderedByLatestCompletion() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        let first = try store.createTask(title: "先创建", projectID: project.id)
        let second = try store.createTask(title: "后创建", projectID: project.id)
        let pending = try store.createTask(title: "未完成", projectID: project.id)
        _ = try store.toggleTask(id: second.id)
        _ = try store.toggleTask(id: first.id)
        try database.queue.write { db in
            try db.execute(sql: "UPDATE task SET completed_at = ? WHERE done = 1",
                           arguments: ["2026-11-02T10:00:00Z"])
        }
        XCTAssertEqual(try store.tasks(projectID: project.id).filter(\.done).map(\.id),
                       [first.id, second.id])
        XCTAssertEqual(try store.listTasks(includeDone: true).filter(\.done).map(\.id),
                       [first.id, second.id])

        try database.queue.write { db in
            try db.execute(sql: "UPDATE task SET completed_at = ? WHERE id = ?",
                           arguments: ["2026-11-02T10:00:00Z", second.id])
            try db.execute(sql: "UPDATE task SET completed_at = ? WHERE id = ?",
                           arguments: ["2026-11-02T11:00:00Z", first.id])
        }

        XCTAssertEqual(try store.tasks(projectID: project.id).map(\.id),
                       [pending.id, first.id, second.id])
        XCTAssertEqual(try store.listTasks(includeDone: true).filter(\.done).map(\.id),
                       [first.id, second.id])

        _ = try store.toggleTask(id: second.id)
        XCTAssertNil(try store.listTasks().first { $0.id == second.id }?.completedAt)
        _ = try store.toggleTask(id: second.id)
        try database.queue.write { db in
            try db.execute(sql: "UPDATE task SET completed_at = ? WHERE id = ?",
                           arguments: ["2026-11-02T12:00:00Z", second.id])
        }
        XCTAssertEqual(try store.tasks(projectID: project.id).filter(\.done).map(\.id),
                       [second.id, first.id])
        XCTAssertEqual(try store.listTasks(includeDone: true).filter(\.done).map(\.id),
                       [second.id, first.id])
    }

    func testTasksAreOrderedNewestFirst() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")
        let today = "2026-10-22"

        _ = try store.createTask(title: "A", projectID: project.id)
        _ = try store.createTask(title: "B", projectID: project.id)
        _ = try store.createTask(title: "C", projectID: project.id)
        _ = try store.createTask(title: "D1", projectID: project.id, plannedDate: today)
        _ = try store.createTask(title: "D2", projectID: project.id, plannedDate: today)

        XCTAssertEqual(
            try store.tasks(projectID: project.id).map(\.title),
            ["D2", "D1", "C", "B", "A"]
        )
        XCTAssertEqual(
            try store.listTasks().map(\.title),
            ["D2", "D1", "C", "B", "A"]
        )
        XCTAssertEqual(
            try store.todayTasks(today: today).map(\.title),
            ["D2", "D1"]
        )
    }
}
