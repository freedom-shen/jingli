import Foundation
import JingliCore

/// 同步的传输层：只负责「把变更送出去 / 拉回来」，合并规则在 JingliCore.SyncStore。
///
/// cursor 由传输层自己解释（CloudKit 是 zone change token 的序列化，假传输是数组下标），
/// 引擎只保证「拉取成功后保存、下次从它继续」。
public protocol SyncTransport: Sendable {
    /// 推送一批本地变更；返回被服务端接受的 changeID。
    func push(_ changes: [SyncChange]) async throws -> [String]

    /// 拉取 cursor 之后的远端变更，并返回新 cursor。
    func pull(cursor: String?) async throws -> (changes: [SyncChange], cursor: String?)
}

public struct SyncReport: Sendable, Equatable {
    public let pushed: Int
    public let pulled: Int
    public let applied: Int
    public let skipped: Int
    public let retried: Int

    public init(pushed: Int, pulled: Int, applied: Int, skipped: Int, retried: Int) {
        self.pushed = pushed
        self.pulled = pulled
        self.applied = applied
        self.skipped = skipped
        self.retried = retried
    }
}
