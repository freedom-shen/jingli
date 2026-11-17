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

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
