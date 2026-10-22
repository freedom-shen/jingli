import XCTest
@testable import JingliCore

final class BackupServiceTests: XCTestCase {
    func testExportAndImportRoundTrip() throws {
        let source = try JingliDatabase.inMemory()
        let sourceStore = WorkspaceStore(database: source)
        let project = try sourceStore.createProject(name: "工作", description: "本周")
        let task = try sourceStore.createTask(
            title: "写周报",
            projectID: project.id,
            lane: "main",
            plannedDate: "2026-10-22"
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let backup = BackupService(database: source, backupDirectory: directory)
        let url = try backup.exportJSON()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let target = try JingliDatabase.inMemory()
        let targetBackup = BackupService(database: target, backupDirectory: directory)
        let summary = try targetBackup.importJSON(from: url)
        XCTAssertEqual(summary.projects, 1)
        XCTAssertEqual(summary.tasks, 1)

        let targetStore = WorkspaceStore(database: target)
        let tasks = try targetStore.listTasks(includeDone: true)
        XCTAssertEqual(tasks.first?.id, task.id)
        XCTAssertEqual(tasks.first?.title, "写周报")
        XCTAssertEqual(tasks.first?.projectID, project.id)
    }

    func testDailyBackupRunsOncePerDay() throws {
        let database = try JingliDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let backup = BackupService(database: database, backupDirectory: directory)
        let first = try backup.dailyBackup()
        XCTAssertNotNil(first)
        XCTAssertNil(try backup.dailyBackup())
        XCTAssertEqual(try backup.listBackups().count, 1)
    }
}
