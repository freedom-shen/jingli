import XCTest
@testable import JingliCore

final class WidgetDataTests: XCTestCase {
    func testLoadsTodaySnapshotReadOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let support = directory.appendingPathComponent("Jingli", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let database = try JingliDatabase.onDisk(at: support.appendingPathComponent("jingli.sqlite"))
        let store = WorkspaceStore(database: database)
        let today = DayKey.make()
        let project = try store.createProject(name: "容器验证")
        let done = try store.createTask(title: "已经做完", projectID: project.id, lane: "main", plannedDate: today)
        let open = try store.createTask(title: "还没做", projectID: project.id, lane: "main", plannedDate: today)
        let temp = try store.createTask(title: "临时一件", lane: "temporary", plannedDate: today)
        try store.startDay(taskIDs: [done.id, open.id, temp.id], today: today)
        _ = try store.toggleTask(id: done.id)

        let snapshot = try XCTUnwrap(WidgetData.load(containerURL: directory, today: today))
        XCTAssertEqual(snapshot.mainTotal, 2)
        XCTAssertEqual(snapshot.mainOpen, 1)
        XCTAssertEqual(snapshot.tempOpen, 1)
        XCTAssertEqual(snapshot.nextTitle, "还没做")

        // 只读：库文件不应被 widget 改坏
        let again = try XCTUnwrap(WidgetData.load(containerURL: directory, today: today))
        XCTAssertEqual(again.nextTitle, snapshot.nextTitle)
    }

    func testMissingDatabaseReturnsNil() {
        XCTAssertNil(WidgetData.load(containerURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)))
    }
}
