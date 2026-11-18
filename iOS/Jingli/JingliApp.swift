import SwiftUI
import JingliCore

@main
struct JingliApp: App {
    @State private var model: IOSAppModel

    init() {
        // Widget / Live Activity 和主 App 共用同一个库
        AppPaths.containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.freedom-shen.jingli")
        // 编译期没有任何地方引用 AppShortcutsProvider，链接器会把这个类型整个丢掉，
        // 于是快捷指令库里能点开、一运行就报 "Couldn't find AppShortcutsProvider"。
        // 这里显式摸一下，保证它的 Swift 元数据留在二进制里。
        _ = JingliShortcuts.appShortcuts.count
        _model = State(initialValue: IOSAppModel())
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { url in
                    // 快捷指令「打开 URL」/ 小组件 / 其它 App：jingli://add?title=…
                    guard url.scheme == "jingli" else { return }
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                    let title = items?.first { $0.name == "title" }?.value
                    model.requestQuickAdd(title: title)
                }
                .onChange(of: scenePhase) { _, phase in
                    // 回到前台补一次同步（后台期间可能错过了对端的写入）
                    if phase == .active {
                        _Concurrency.Task { await model.syncNow() }
                    }
                }
        }
    }
}
