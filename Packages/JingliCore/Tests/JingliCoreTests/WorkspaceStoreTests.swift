import XCTest
@testable import JingliCore

final class WorkspaceStoreTests: XCTestCase {
    func testCreateProjectAndTask() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        let project = try store.createProject(name: "工作")
        let task = try store.createTask(title: "写周报", projectID: project.id)

        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.lane, "main")
        XCTAssertEqual(try store.taskCount(), 1)
    }

    func testEmptyTitleThrows() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        XCTAssertThrowsError(try store.createTask(title: "   "))
        XCTAssertThrowsError(try store.createProject(name: ""))
    }

    func testProjectTasksCannotBeTemporary() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let project = try store.createProject(name: "工作")

        XCTAssertThrowsError(
            try store.createTask(title: "插单", projectID: project.id, lane: "temporary")
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "项目里的任务只能是主线；临时任务不能挂项目"
            )
        }
        XCTAssertEqual(try store.taskCount(), 0)
    }

    func testTaskEstimateRoundTrip() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        let task = try store.createTask(title: "排查地图", lane: "temporary", estimate: 3)
        XCTAssertEqual(task.estimate, 3)

        let updated = try store.updateTask(
            id: task.id,
            title: task.title,
            note: "## 背景\n- [ ] 复现",
            estimate: 5
        )
        XCTAssertEqual(updated?.estimate, 5)
        XCTAssertEqual(updated?.note, "## 背景\n- [ ] 复现")

        let cleared = try store.updateTask(
            id: task.id,
            title: task.title,
            note: updated?.note ?? "",
            estimate: nil
        )
        XCTAssertNil(cleared?.estimate)
    }

    func testEstimateIsClamped() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)

        XCTAssertEqual(try store.createTask(title: "估太小", estimate: 0).estimate, 1)
        XCTAssertEqual(try store.createTask(title: "估太大", estimate: 99).estimate, 32)
    }
}
