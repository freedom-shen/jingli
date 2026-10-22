import Darwin
import Foundation

public final class AgentServer: @unchecked Sendable {
    private let store: WorkspaceStore
    private let acceptQueue = DispatchQueue(label: "jingli.agent.accept")
    private let clientQueue = DispatchQueue(
        label: "jingli.agent.clients",
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var socketPath = ""

    public init(database: JingliDatabase) {
        self.store = WorkspaceStore(database: database)
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
        defer { close(client) }
        guard let line = readLine(client), !line.isEmpty else { return }
        writeAll(client, process(line) + "\n")
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

    private func process(_ line: String) -> String {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else {
            return errorResponse(id: NSNull(), code: -32700, message: "parse error")
        }

        let id = object["id"] ?? NSNull()
        let params = object["params"] as? [String: Any] ?? [:]

        do {
            let result: Any
            switch method {
            case "ping":
                result = ["pong": true]
            case "task.create":
                let title = params["title"] as? String ?? ""
                let projectID = params["projectId"] as? String
                let lane = params["lane"] as? String ?? "main"
                let task = try store.createTask(
                    title: title,
                    projectID: projectID,
                    lane: lane
                )
                result = ["id": task.id, "title": task.title, "lane": task.lane]
            case "task.count":
                result = ["count": try store.taskCount()]
            default:
                return errorResponse(id: id, code: -32601, message: "method not found")
            }

            let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
            let data = try JSONSerialization.data(withJSONObject: response)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return errorResponse(id: id, code: -32000, message: "\(error)")
        }
    }

    private func errorResponse(id: Any, code: Int, message: String) -> String {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
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
