import Foundation

public enum TimerPhase: String, Codable, Sendable {
    case ready
    case running
    case paused
    case finished
}

public struct FocusTimer: Codable, Equatable, Sendable {
    public static let defaultDurationMs = 25 * 60 * 1000

    public private(set) var taskIDs: [String]
    public private(set) var phase: TimerPhase
    public private(set) var remainingMs: Int
    public private(set) var endsAt: Int64?
    public let durationMs: Int
    public private(set) var sessionID: String?
    public let sessionDate: String
    public private(set) var focusModeOn: Bool
    public private(set) var focusModeOwned: Bool

    public init?(
        taskIDs: [String],
        sessionDate: String,
        durationMs: Int = FocusTimer.defaultDurationMs
    ) {
        let unique = Self.normalized(taskIDs)
        guard !unique.isEmpty, durationMs > 0 else { return nil }
        self.taskIDs = unique
        self.phase = .ready
        self.remainingMs = durationMs
        self.endsAt = nil
        self.durationMs = durationMs
        self.sessionID = nil
        self.sessionDate = sessionDate
        self.focusModeOn = false
        self.focusModeOwned = false
    }

    public var isActive: Bool {
        phase == .running || phase == .paused
    }

    public var isFinished: Bool {
        phase == .finished
    }

    public mutating func start(now: Int64, sessionID: String) {
        guard phase == .ready else { return }
        self.sessionID = sessionID
        phase = .running
        remainingMs = durationMs
        endsAt = now + Int64(durationMs)
    }

    public func remaining(now: Int64) -> Int {
        switch phase {
        case .ready, .paused:
            return remainingMs
        case .running:
            guard let endsAt else { return 0 }
            return max(0, min(remainingMs, Int(endsAt - now)))
        case .finished:
            return 0
        }
    }

    public mutating func tick(now: Int64) {
        guard phase == .running else { return }
        if remaining(now: now) == 0 {
            phase = .finished
            remainingMs = 0
            endsAt = nil
        }
    }

    public mutating func pause(now: Int64) {
        tick(now: now)
        guard phase == .running else { return }
        remainingMs = remaining(now: now)
        endsAt = nil
        phase = .paused
    }

    public mutating func resume(now: Int64) {
        guard phase == .paused else { return }
        phase = .running
        endsAt = now + Int64(remainingMs)
    }

    public func addingTask(_ taskID: String) -> FocusTimer {
        guard !taskIDs.contains(taskID) else { return self }
        var copy = self
        copy.taskIDs.append(taskID)
        return copy
    }

    public func removingTask(_ taskID: String) -> FocusTimer? {
        var copy = self
        copy.taskIDs.removeAll { $0 == taskID }
        return copy.taskIDs.isEmpty ? nil : copy
    }

    public mutating func setFocusMode(on: Bool, owned: Bool) {
        focusModeOn = on
        focusModeOwned = owned
    }

    public static func format(_ milliseconds: Int) -> String {
        let seconds = max(0, Int(ceil(Double(milliseconds) / 1000.0)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private static func normalized(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return false }
            seen.insert(trimmed)
            return true
        }
    }
}
