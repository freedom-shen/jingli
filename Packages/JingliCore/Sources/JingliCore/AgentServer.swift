import Darwin
import Foundation
import GRDB

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

public final class AgentServer: @unchecked Sendable {
    private let router: AgentCommandRouter
    private let acceptQueue = DispatchQueue(label: "jingli.agent.accept")
    private let clientQueue = DispatchQueue(
        label: "jingli.agent.clients",
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var socketPath = ""

    public init(
        database: JingliDatabase,
        focus: FocusAgentHandling? = nil,
        onChange: (@Sendable () -> Void)? = nil,
        actor: String = "agent"
    ) {
        self.router = AgentCommandRouter(
            database: database,
            focus: focus,
            onChange: onChange,
            actor: actor
        )
    }

    deinit {
        stop()
    }

    public func start(socketURL: URL) throws {
        let path = socketURL.path
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = path.withCString { unlink($0) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ServerError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            pathBytes.withUnsafeBytes { source in
                raw.copyBytes(from: source)
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw ServerError.bindFailed(code)
        }

        _ = path.withCString { chmod($0, 0o600) }

        guard listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            _ = path.withCString { unlink($0) }
            throw ServerError.listenFailed(code)
        }

        lock.lock()
        listenFD = fd
        running = true
        socketPath = path
        lock.unlock()

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        lock.lock()
        let fd = listenFD
        let path = socketPath
        running = false
        listenFD = -1
        socketPath = ""
        lock.unlock()

        if fd >= 0 {
            close(fd)
        }
        if !path.isEmpty {
            _ = path.withCString { unlink($0) }
        }
    }

    private func acceptLoop() {
        while true {
            lock.lock()
            let isRunning = running
            let fd = listenFD
            lock.unlock()

            guard isRunning, fd >= 0 else { return }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { continue }

            clientQueue.async { [weak self] in
                self?.handle(client: client)
            }
        }
    }

    private func handle(client: Int32) {
        var one: Int32 = 1
        _ = setsockopt(
            client,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &one,
            socklen_t(MemoryLayout<Int32>.size)
        )
        defer { close(client) }
        guard let line = readLine(client), !line.isEmpty else { return }
        writeAll(client, router.process(line: line) + "\n")
    }

    private func readLine(_ fd: Int32) -> String? {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count <= 0 { break }
            if byte == 0x0A { break }
            data.append(byte)
            if data.count > 1_000_000 { break }
        }
        return String(data: data, encoding: .utf8)
    }

    private func writeAll(_ fd: Int32, _ string: String) {
        let data = Data(string.utf8)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(fd, base.advanced(by: offset), raw.count - offset)
                if count <= 0 { break }
                offset += count
            }
        }
    }
}

public enum ServerError: Error {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case pathTooLong
}
