import Foundation
import Intents

public protocol FocusStatusReading: Sendable {
    /// nil 表示无法判断（未授权 / 读取失败）。
    func isFocused() -> Bool?
}

public struct SystemFocusStatus: FocusStatusReading {
    public init() {}

    public func isFocused() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }
}

public enum FocusStartOutcome: Sendable, Equatable {
    /// 应用开启了勿扰，并负责在结束 / 退出时关闭。
    case enabled
    /// 开始前已经有 Focus，应用不接管。
    case alreadyFocused
    /// 快捷指令未配置，无法联动。
    case unavailable
}

/// 统一管理勿扰所有权与串行执行，避免快速开始 / 结束导致顺序错乱。
public final class FocusModeCoordinator: @unchecked Sendable {
    public static let shared = FocusModeCoordinator()

    private let controller: FocusController
    private let status: FocusStatusReading
    private let queue = DispatchQueue(label: "com.freedom-shen.jingli.focus-mode")
    private let lock = NSLock()
    private var ownedStorage = false

    public init(
        controller: FocusController = FocusController.shared,
        status: FocusStatusReading = SystemFocusStatus()
    ) {
        self.controller = controller
        self.status = status
    }

    public var isOwned: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownedStorage
    }

    @discardableResult
    public func begin() -> FocusStartOutcome {
        if status.isFocused() == true {
            setOwned(false)
            return .alreadyFocused
        }
        guard controller.isConfigured() else {
            setOwned(false)
            return .unavailable
        }
        setOwned(true)
        queue.async { [controller] in
            try? controller.enable()
        }
        return .enabled
    }

    /// 仅当勿扰由本应用开启时才关闭。
    public func end() {
        guard setOwned(false) else { return }
        queue.async { [controller] in
            try? controller.disable()
        }
    }

    /// 退出 App 时使用：最多等待 1 秒，避免把勿扰留在开启状态。
    public func endAndWait(timeout: TimeInterval = 1.0) {
        guard setOwned(false) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        queue.async { [controller] in
            try? controller.disable()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    /// App 启动时恢复活跃轮次的勿扰；不读取 Focus 状态，直接补开。
    public func restore() {
        setOwned(true)
        queue.async { [controller] in
            try? controller.enable()
        }
    }

    private func setOwned(_ value: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let previous = ownedStorage
        ownedStorage = value
        return previous
    }
}
