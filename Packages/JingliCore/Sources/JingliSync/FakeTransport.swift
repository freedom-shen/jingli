import Foundation
import JingliCore

/// 内存传输层：给测试和「同步调试页」用，不联网。
public actor FakeTransport: SyncTransport {
    private var log: [SyncChange] = []
    private var accepted: Set<String> = []
    private var failNextPush = false

    public init() {}

    public func setFailNextPush(_ value: Bool) { failNextPush = value }

    public func push(_ changes: [SyncChange]) async throws -> [String] {
        if failNextPush {
            failNextPush = false
            throw SyncTransportError.unavailable
        }
        for change in changes where !accepted.contains(change.changeID) {
            log.append(change)
            accepted.insert(change.changeID)
        }
        return changes.map(\.changeID)
    }

    public func pull(cursor: String?) async throws -> (changes: [SyncChange], cursor: String?) {
        let start = cursor.flatMap(Int.init) ?? 0
        let slice = Array(log.dropFirst(min(start, log.count)))
        return (slice, String(log.count))
    }

    public func count() -> Int { log.count }
}

public enum SyncTransportError: Error, LocalizedError {
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "同步服务暂时不可用"
        }
    }
}
