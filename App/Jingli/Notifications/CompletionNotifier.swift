import Foundation
import UserNotifications

final class CompletionNotifier: @unchecked Sendable {
    static let shared = CompletionNotifier()

    private var requested = false

    private init() {}

    func requestAuthorization() {
        guard ProcessInfo.processInfo.environment["JINGLI_NO_NOTIFICATIONS"] != "1" else {
            return
        }
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func notify(taskCount: Int, durationSeconds: Int) {
        notify(
            title: "本轮番茄钟完成",
            body: "\(taskCount) 件任务 · \(durationSeconds / 60) 分钟"
        )
    }

    func notify(title: String, body: String) {
        guard ProcessInfo.processInfo.environment["JINGLI_NO_NOTIFICATIONS"] != "1" else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
