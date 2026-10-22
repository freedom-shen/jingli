import SwiftUI

@main
struct JingliApp: App {
    var body: some Scene {
        WindowGroup("精力管理") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
    }
}
