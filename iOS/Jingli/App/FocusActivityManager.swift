@preconcurrency import ActivityKit
import Foundation

/// 锁屏 / 动态岛的番茄倒计时。失败不影响计时本身。
@MainActor
final class FocusActivityManager {
    static let shared = FocusActivityManager()

    private var activity: Activity<FocusActivityAttributes>?

    func start(taskTitle: String, taskCount: Int, endsAt: Date, remainingSeconds: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[Jingli] Live Activity 未启用")
            return
        }
        end()
        let attributes = FocusActivityAttributes(taskTitle: taskTitle, taskCount: taskCount)
        let state = FocusActivityAttributes.ContentState(
            endsAt: endsAt, isPaused: false, remainingSeconds: remainingSeconds
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: endsAt)
            )
            let live = Activity<FocusActivityAttributes>.activities
            NSLog("[Jingli] Live Activity 已开始，当前活动数=\(live.count)")
            for item in live {
                NSLog("[Jingli] 活动 \(item.id) state=\(String(describing: item.content.state.isPaused)) active=\(item.activityState == .active)")
            }
        } catch {
            NSLog("[Jingli] Live Activity 启动失败：\(error)")
        }
    }

    func update(isPaused: Bool, endsAt: Date, remainingSeconds: Int) {
        guard let activity else { return }
        let state = FocusActivityAttributes.ContentState(
            endsAt: endsAt, isPaused: isPaused, remainingSeconds: remainingSeconds
        )
        Task { await activity.update(.init(state: state, staleDate: endsAt)) }
    }

    func end() {
        guard let activity else { return }
        let finished = activity
        self.activity = nil
        Task { await finished.end(nil, dismissalPolicy: .immediate) }
    }
}
