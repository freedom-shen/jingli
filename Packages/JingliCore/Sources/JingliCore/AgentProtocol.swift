import Foundation

@MainActor
public protocol FocusAgentHandling: AnyObject, Sendable {
    func agentFocusStatus() throws -> [String: Any]
    func agentStartFocus(taskIDs: [String]) throws -> [String: Any]
    func agentPauseFocus() throws -> [String: Any]
    func agentResumeFocus() throws -> [String: Any]
    func agentStopFocus() throws -> [String: Any]
    func agentAddFocusTask(taskID: String) throws -> [String: Any]
    func agentRemoveFocusTask(taskID: String) throws -> [String: Any]
    func agentStartBreak() throws -> [String: Any]
    func agentSkipBreak() throws -> [String: Any]
}

public enum AgentError: Error, LocalizedError {
    case invalidParams(String)
    case notFound(String)
    case confirmRequired
    case focusUnavailable
    case undoUnavailable

    public var errorDescription: String? {
        switch self {
        case let .invalidParams(message): return "参数不正确：\(message)"
        case let .notFound(message): return "找不到：\(message)"
        case .confirmRequired: return "破坏性操作需要 --confirm"
        case .focusUnavailable: return "App 未连接计时器"
        case .undoUnavailable: return "没有可撤销的操作"
        }
    }
}
