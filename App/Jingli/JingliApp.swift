import SwiftUI

@main
struct JingliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("精力管理") {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .newItem) {
                Button("快速命令") {
                    AppServices.shared.model.openCommandBar()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPanel(model: AppServices.shared.model)
        } label: {
            MenuBarLabel(model: AppServices.shared.model)
        }
        .menuBarExtraStyle(.window)
    }
}
