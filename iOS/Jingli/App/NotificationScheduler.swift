import Foundation
import UserNotifications

/// 本地通知：计时结束提醒。App 在前台时不打扰（系统默认），切后台/锁屏时才有用。
enum NotificationScheduler {
    private static let focusID = "jingli.focus.end"
    private static let breakID = "jingli.break.end"
    nonisolated(unsafe) private static var asked = false

    static func requestAuthorizationIfNeeded() async {
        guard !asked else { return }
        asked = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    static func scheduleFocusEnd(after seconds: Int, taskTitle: String) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "专注结束"
        content.body = "「\(taskTitle)」这一轮完成了，回来结算一下。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, TimeInterval(seconds)), repeats: false
        )
        let request = UNNotificationRequest(identifier: focusID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            NSLog("[Jingli] 通知排期 \(error == nil ? "成功" : "失败：\(String(describing: error))")")
        }
    }

    static func scheduleBreakEnd(after seconds: Int) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "该回到清单了。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, TimeInterval(seconds)), repeats: false
        )
        let request = UNNotificationRequest(identifier: breakID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelFocusEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [focusID])
    }

    static func cancelBreakEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [breakID])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [focusID, breakID])
    }
}
