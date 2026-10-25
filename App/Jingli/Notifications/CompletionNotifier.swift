import AppKit
import Foundation
import UserNotifications

final class CompletionNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CompletionNotifier()

    static let categoryID = "FOCUS_COMPLETE"
    static let longBreakCategoryID = "FOCUS_COMPLETE_LONG_BREAK"
    static let breakActionID = "JINGLI_BREAK"
    static let closeActionID = "JINGLI_CLOSE"

    private var requested = false
    private var configured = false

    private override init() {
        super.init()
    }

    func configure() {
        guard !configured else { return }
        configured = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let breakAction = UNNotificationAction(
            identifier: Self.breakActionID,
            title: "开始休息 5 分钟",
            options: [.foreground]
        )
        let closeAction = UNNotificationAction(
            identifier: Self.closeActionID,
            title: "回到清单",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [breakAction, closeAction],
            intentIdentifiers: [],
            options: []
        )
        let longBreakAction = UNNotificationAction(
            identifier: Self.breakActionID,
            title: "连续 4 个钟了，休息一下",
            options: [.foreground]
        )
        let longBreakCategory = UNNotificationCategory(
            identifier: Self.longBreakCategoryID,
            actions: [longBreakAction, closeAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, longBreakCategory])
    }

    func requestAuthorization() {
        guard ProcessInfo.processInfo.environment["JINGLI_NO_NOTIFICATIONS"] != "1" else {
            return
        }
        configure()
        guard !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { _, _ in }
    }

    func notify(taskCount: Int, durationSeconds: Int, longBreak: Bool = false) {
        notify(
            title: "本轮番茄钟完成",
            body: longBreak
                ? "已连续完成 4 个番茄钟 · 休息 25 分钟"
                : "\(taskCount) 件任务 · \(durationSeconds / 60) 分钟",
            category: longBreak ? Self.longBreakCategoryID : Self.categoryID
        )
    }

    func notify(title: String, body: String, category: String? = nil) {
        guard ProcessInfo.processInfo.environment["JINGLI_NO_NOTIFICATIONS"] != "1" else {
            return
        }
        configure()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category ?? Self.categoryID

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        completionHandler()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let model = AppServices.shared.model
                switch action {
                case Self.breakActionID:
                    NSApp.activate(ignoringOtherApps: true)
                    model.startBreak()
                case Self.closeActionID:
                    model.dismissCompletion()
                default:
                    NSApp.activate(ignoringOtherApps: true)
                    model.dismissCompletion()
                }
            }
        }
    }
}
