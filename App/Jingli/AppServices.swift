import Foundation
import JingliCore

@MainActor
final class AppServices {
    static let shared = AppServices()

    let database: JingliDatabase
    let store: WorkspaceStore

    private init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            database = try! JingliDatabase.inMemory()
            store = WorkspaceStore(database: database)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: AppPaths.supportDirectory,
                withIntermediateDirectories: true
            )
            database = try JingliDatabase.onDisk(at: AppPaths.databaseURL)
        } catch {
            database = try! JingliDatabase.inMemory()
        }
        store = WorkspaceStore(database: database)
    }
}
