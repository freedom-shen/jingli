import Foundation
import JingliCore
import OSLog

/// 数据库打不开时的启动错误；App 会提示后退出，不会带着临时库继续跑。
struct StartupFailure {
    let title: String
    let detail: String
    let supportDirectory: URL
}

@MainActor
final class AppServices {
    static let shared = AppServices()

    private static let databaseLog = Logger(
        subsystem: "com.freedom-shen.jingli",
        category: "database"
    )

    let database: JingliDatabase
    let store: WorkspaceStore
    let model: AppModel
    let startupFailure: StartupFailure?

    private init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            database = try! JingliDatabase.inMemory()
            store = WorkspaceStore(database: database)
            model = AppModel(store: store)
            startupFailure = nil
            return
        }

        let database: JingliDatabase
        let failure: StartupFailure?
        do {
            try FileManager.default.createDirectory(
                at: AppPaths.supportDirectory,
                withIntermediateDirectories: true
            )
            database = try JingliDatabase.onDisk(at: AppPaths.databaseURL)
            failure = nil
        } catch {
            Self.databaseLog.error(
                "open database failed: \(String(describing: error), privacy: .public)"
            )
            database = Self.makeMemoryDatabase()
            failure = StartupFailure(
                title: "打不开本地数据库",
                detail: """
                \(AppPaths.databaseURL.path)

                错误：\(error.localizedDescription)

                为避免新数据写进临时库后丢失，应用不会继续运行。
                """,
                supportDirectory: AppPaths.supportDirectory
            )
        }

        let store = WorkspaceStore(database: database)
        let model = AppModel(store: store)
        self.database = database
        self.store = store
        self.model = model
        self.startupFailure = failure
    }

    private static func makeMemoryDatabase() -> JingliDatabase {
        do {
            return try JingliDatabase.inMemory()
        } catch {
            fatalError("无法创建内存数据库：\(error)")
        }
    }
}
