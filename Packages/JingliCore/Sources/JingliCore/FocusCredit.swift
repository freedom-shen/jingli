import Foundation

/// 共享一轮番茄钟时，按「到时仍参与的任务数」均分。
public enum FocusCredit {
    public static func shares(participants: Int) -> [Double] {
        guard participants > 0 else { return [] }
        return Array(repeating: 1.0 / Double(participants), count: participants)
    }

    /// 只用于显示：最多两位小数；累计精度不丢。
    public static func roundedForDisplay(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
