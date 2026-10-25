import Foundation

/// 连续完成番茄钟的计数：一轮中途被废弃即清零；
/// 满 `threshold` 个触发一次长休，随后计数重新开始。
public struct FocusStreak: Equatable, Sendable {
    public static let threshold = 4

    public let count: Int

    public init(count: Int = 0) {
        self.count = max(0, count)
    }

    /// 记录一轮完成；`earnedLongBreak` 为 true 表示刚满 threshold。
    public func completed() -> (streak: FocusStreak, earnedLongBreak: Bool) {
        let next = count + 1
        if next >= Self.threshold {
            return (FocusStreak(count: 0), true)
        }
        return (FocusStreak(count: next), false)
    }

    public func reset() -> FocusStreak {
        FocusStreak(count: 0)
    }
}
