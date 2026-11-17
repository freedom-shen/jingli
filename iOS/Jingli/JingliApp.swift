import SwiftUI
import JingliCore

@main
struct JingliApp: App {
    @State private var model: IOSAppModel

    init() {
        // Widget / Live Activity 和主 App 共用同一个库
        AppPaths.containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.freedom-shen.jingli")
        _model = State(initialValue: IOSAppModel())
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    // 回到前台补一次同步（后台期间可能错过了对端的写入）
                    if phase == .active {
                        _Concurrency.Task { await model.syncNow() }
                    }
                }
        }
    }
}
