import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// 主 App 与 Widget 扩展共用的 Live Activity 描述。
public struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endsAt: Date
        public var isPaused: Bool
        public var remainingSeconds: Int

        public init(endsAt: Date, isPaused: Bool, remainingSeconds: Int) {
            self.endsAt = endsAt
            self.isPaused = isPaused
            self.remainingSeconds = remainingSeconds
        }
    }

    public var taskTitle: String
    public var taskCount: Int

    public init(taskTitle: String, taskCount: Int) {
        self.taskTitle = taskTitle
        self.taskCount = taskCount
    }
}
#endif
