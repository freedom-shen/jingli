import Darwin
import Foundation

/// 手机网页端：一个极简 HTTP/1.1 服务，给 Tailscale / 局域网里的手机浏览器用。
///
/// 设计边界：
/// - 只做「看今天 / 加临时任务 / 勾完成 / 开启今天」；不跑番茄计时、不暴露设置。
/// - 所有写操作复用 `AgentCommandRouter`，和 CLI / Agent 走同一套业务规则与审计日志。
/// - 用一次性 token 鉴权；token 只存在本地 `setting` 表，不参与同步、不进仓库。
/// - 明文 HTTP 只在 Tailscale 虚拟局域网或家庭局域网内使用；token 等同密码。
public final class RemoteWebServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8787

    public enum WebError: Error, LocalizedError {
        case socketFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
        case nameFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case let .socketFailed(code):
                return "手机网页服务创建失败（errno \(code)）"
            case let .bindFailed(code):
                return code == EADDRINUSE
                    ? "端口被占用，换一个端口或关掉占用它的程序"
                    : "手机网页服务绑定端口失败（errno \(code)）"
            case let .listenFailed(code):
                return "手机网页服务监听失败（errno \(code)）"
            case let .nameFailed(code):
                return "手机网页服务读取端口失败（errno \(code)）"
            }
        }
    }

    private let router: AgentCommandRouter
    private let token: String
    private let requestedPort: UInt16
    private let acceptQueue = DispatchQueue(label: "jingli.web.accept")
    private let clientQueue = DispatchQueue(
        label: "jingli.web.clients",
        attributes: .concurrent
    )
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private var boundPort: UInt16 = 0

    public init(
        database: JingliDatabase,
        token: String,
        port: UInt16 = RemoteWebServer.defaultPort,
        onChange: (@Sendable () -> Void)? = nil
    ) {
        precondition(!token.isEmpty, "token 不能为空")
        self.router = AgentCommandRouter(
            database: database,
            focus: nil,
            onChange: onChange,
            actor: "web"
        )
        self.token = token
        self.requestedPort = port
    }

    deinit {
        stop()
    }

    public var port: UInt16 {
        lock.lock()
        defer { lock.unlock() }
        return boundPort
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    public func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WebError.socketFailed(errno) }

        var reuse: Int32 = 1
        _ = setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = 0
        address.sin_port = requestedPort.bigEndian

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw WebError.bindFailed(code)
        }

        guard listen(fd, 64) == 0 else {
            let code = errno
            close(fd)
            throw WebError.listenFailed(code)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else {
            let code = errno
            close(fd)
            throw WebError.nameFailed(code)
        }

        lock.lock()
        listenFD = fd
        running = true
        boundPort = UInt16(bigEndian: actual.sin_port)
        lock.unlock()

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    public func stop() {
        lock.lock()
        let fd = listenFD
        running = false
        listenFD = -1
        lock.unlock()
        if fd >= 0 {
            close(fd)
        }
    }

    // MARK: - Accept / request handling

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
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        _ = setsockopt(
            client,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        defer { close(client) }

        guard let request = readRequest(client) else {
            respond(.badRequest("无法解析请求"), to: client)
            return
        }
        let response = route(request)
        respond(response, to: client, request: request)
    }

    private func readRequest(_ fd: Int32) -> HTTPRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let headerEnd = Data("\r\n\r\n".utf8)

        // 读到 header 结束
        while data.range(of: headerEnd) == nil {
            if data.count > 64 * 1024 { return nil }
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { return data.isEmpty ? nil : parseRequest(data) }
            data.append(buffer, count: count)
        }

        guard let range = data.range(of: headerEnd) else { return nil }
        let headerData = data[..<range.lowerBound]
        var body = Data(data[range.upperBound...])

        guard let head = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        if body.count < contentLength {
            let remaining = contentLength - body.count
            if remaining > 1_000_000 { return nil }
            var rest = [UInt8](repeating: 0, count: remaining)
            var offset = 0
            while offset < remaining {
                let count = rest.withUnsafeMutableBytes { raw -> Int in
                    read(fd, raw.baseAddress!.advanced(by: offset), remaining - offset)
                }
                if count <= 0 { break }
                body.append(contentsOf: rest[0..<count])
                offset += count
            }
        }

        let target = String(parts[1])
        let path: String
        var query: [String: String] = [:]
        if let question = target.firstIndex(of: "?") {
            path = String(target[..<question])
            query = Self.parseQuery(String(target[target.index(after: question)...]))
        } else {
            path = target
        }

        return HTTPRequest(
            method: String(parts[0]).uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }

    private func parseRequest(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let first = text.components(separatedBy: "\r\n").first ?? ""
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var path = String(parts[1])
        var query: [String: String] = [:]
        if let question = path.firstIndex(of: "?") {
            query = Self.parseQuery(String(path[path.index(after: question)...]))
            path = String(path[..<question])
        }
        return HTTPRequest(
            method: String(parts[0]).uppercased(),
            path: path,
            query: query,
            headers: [:],
            body: Data()
        )
    }

    private static func parseQuery(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            let decodedKey = key.removingPercentEncoding ?? String(key)
            let decodedValue = value
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding ?? value
            result[decodedKey] = decodedValue
        }
        return result
    }

    // MARK: - Routing

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.path

        if path == "/" || path == "/index.html" {
            if request.method == "GET" || request.method == "HEAD" {
                return .html(RemoteWebPage.html)
            }
            return .methodNotAllowed
        }
        if path == "/favicon.ico" {
            return HTTPResponse(status: 204, reason: "No Content", contentType: nil, body: Data())
        }
        if path == "/api/ping" {
            return .json(["ok": true, "app": "Jingli"])
        }

        guard isAuthorized(request) else {
            return .unauthorized
        }

        do {
            switch (request.method, path) {
            case ("GET", "/api/today"):
                let today = try router.call(method: "today")
                let stats = try router.call(method: "stats.today")
                return .json([
                    "ok": true,
                    "date": DayKey.make(),
                    "today": today,
                    "stats": stats,
                    "serverTime": ISO8601DateFormatter().string(from: Date())
                ])

            case ("POST", "/api/tasks"):
                return try createTask(request)
            case ("POST", "/api/day/start"):
                let result = try router.call(method: "day.start")
                return .json(["ok": true, "result": result])

            default:
                if request.method == "POST", path.hasPrefix("/api/tasks/") {
                    return try toggleTask(request, path: path)
                }
                return .notFound
            }
        } catch {
            return .json(
                ["ok": false, "error": error.localizedDescription],
                status: 400
            )
        }
    }

    private func createTask(_ request: HTTPRequest) throws -> HTTPResponse {
        guard let object = try jsonObject(request.body),
              let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return .json(["ok": false, "error": "任务标题不能为空"], status: 400)
        }
        var params: [String: Any] = [
            "title": String(title.prefix(120)),
            "lane": "temporary",
            "undated": true
        ]
        if let note = object["note"] as? String, !note.isEmpty {
            params["note"] = String(note.prefix(400))
        }
        let created = try router.call(method: "task.create", params: params)
        guard let payload = created as? [String: Any],
              let id = payload["id"] as? String else {
            return .json(["ok": false, "error": "创建任务失败"], status: 500)
        }
        _ = try? router.call(method: "day.add", params: ["taskIds": [id]])
        return .json(["ok": true, "task": payload])
    }

    private func toggleTask(_ request: HTTPRequest, path: String) throws -> HTTPResponse {
        let prefix = "/api/tasks/"
        let suffix = "/toggle"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else {
            return .notFound
        }
        let start = path.index(path.startIndex, offsetBy: prefix.count)
        let end = path.index(path.endIndex, offsetBy: -suffix.count)
        let id = String(path[start..<end])
        guard !id.isEmpty else { return .notFound }

        guard let object = try jsonObject(request.body),
              let done = object["done"] as? Bool else {
            return .json(["ok": false, "error": "缺少 done"], status: 400)
        }
        let result = try router.call(
            method: done ? "task.complete" : "task.reopen",
            params: ["id": id]
        )
        return .json(["ok": true, "task": result])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any]? {
        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Auth

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        if let value = request.query["t"] ?? request.query["token"], constantTimeEquals(value) {
            return true
        }
        if let value = request.headers["x-jingli-token"], constantTimeEquals(value) {
            return true
        }
        if let cookie = request.headers["cookie"] {
            for item in cookie.split(separator: ";") {
                let parts = item.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                if name == "jingli_token" {
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    if constantTimeEquals(value) { return true }
                }
            }
        }
        return false
    }

    private func constantTimeEquals(_ candidate: String) -> Bool {
        let lhs = Array(candidate.utf8)
        let rhs = Array(token.utf8)
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for index in lhs.indices {
            diff |= lhs[index] ^ rhs[index]
        }
        return diff == 0
    }

    // MARK: - Response

    private func respond(_ response: HTTPResponse, to fd: Int32, request: HTTPRequest? = nil) {
        var head = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        if let contentType = response.contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(response.body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Referrer-Policy: no-referrer\r\n"
        head += "Connection: close\r\n"

        // 首次带 token 打开时种 cookie，后续请求就不必把 token 留在地址栏。
        if let request,
           let value = request.query["t"] ?? request.query["token"],
           constantTimeEquals(value) {
            head += "Set-Cookie: jingli_token=\(token); Path=/; Max-Age=31536000; HttpOnly; SameSite=Lax\r\n"
        }

        head += "\r\n"
        var data = Data(head.utf8)
        data.append(response.body)

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

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

private struct HTTPResponse {
    let status: Int
    let reason: String
    let contentType: String?
    let body: Data

    static func json(_ object: [String: Any], status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: status,
            reason: status == 200 ? "OK" : "Error",
            contentType: "application/json; charset=utf-8",
            body: data
        )
    }

    static func html(_ html: String) -> HTTPResponse {
        HTTPResponse(
            status: 200,
            reason: "OK",
            contentType: "text/html; charset=utf-8",
            body: Data(html.utf8)
        )
    }

    static func badRequest(_ message: String) -> HTTPResponse {
        HTTPResponse(
            status: 400,
            reason: "Bad Request",
            contentType: "text/plain; charset=utf-8",
            body: Data(message.utf8)
        )
    }

    static var unauthorized: HTTPResponse {
        json(["ok": false, "error": "未配对：请用设置页里带 token 的链接打开"], status: 401)
    }

    static var notFound: HTTPResponse {
        json(["ok": false, "error": "not found"], status: 404)
    }

    static var methodNotAllowed: HTTPResponse {
        json(["ok": false, "error": "method not allowed"], status: 405)
    }
}
