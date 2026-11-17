import SwiftUI

@main
struct JingliApp: App {
    @State private var model = IOSAppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
