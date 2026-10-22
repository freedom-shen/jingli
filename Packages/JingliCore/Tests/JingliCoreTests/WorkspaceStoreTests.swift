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
}
