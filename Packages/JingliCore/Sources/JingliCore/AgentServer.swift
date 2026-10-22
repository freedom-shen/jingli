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
    func agentNextRound() throws -> [String: Any]
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
    private let store: WorkspaceStore
    private let focus: FocusAgentHandling?
    private let onChange: (@Sendable () -> Void)?
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
        onChange: (@Sendable () -> Void)? = nil
    ) {
        self.store = WorkspaceStore(database: database)
        self.focus = focus
        self.onChange = onChange
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
            let result = try dispatch(method: method, params: params)
            let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
            let data = try JSONSerialization.data(withJSONObject: response)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return errorResponse(id: id, code: -32000, message: "\(error.localizedDescription)")
        }
    }

    private func dispatch(method: String, params: [String: Any]) throws -> Any {
        switch method {
        case "ping":
            return ["pong": true]

        case "today":
            let snapshot = try store.snapshot()
            return [
                "dayStarted": snapshot.dayStarted,
                "selection": snapshot.selection,
                "tasks": snapshot.todayTasks.map(taskPayload),
                "projects": snapshot.projects.map(projectPayload)
            ]

        case "task.create":
            let title = try string(params, "title")
            let lane = params["lane"] as? String ?? "main"
            let projectID = try resolveProjectID(params)
            let plannedDate = resolveDate(params["date"])
            let task = try store.createTask(
                title: title,
                projectID: projectID,
                lane: lane,
                plannedDate: plannedDate
            )
            try record("task.create", payload: ["id": task.id], undo: ["kind": "task.delete", "id": task.id])
            changed()
            return taskPayload(task)

        case "task.count":
            return ["count": try store.taskCount()]

        case "task.list":
            let includeDone = params["includeDone"] as? Bool ?? false
            let tasks: [Task]
            if let projectID = params["projectId"] as? String {
                tasks = try store.tasks(projectID: projectID)
            } else {
                tasks = try store.listTasks(includeDone: includeDone)
            }
            return ["tasks": tasks.map(taskPayload)]

        case "task.update":
            let id = try string(params, "id")
            guard let current = try store.listTasks(includeDone: true).first(where: { $0.id == id }) else {
                throw AgentError.notFound("task \(id)")
            }
            let title = params["title"] as? String ?? current.title
            let note = params["note"] as? String ?? current.note
            guard let updated = try store.updateTask(id: id, title: title, note: note) else {
                throw AgentError.notFound("task \(id)")
            }
            try record(
                "task.update",
                payload: ["id": id],
                undo: [
                    "kind": "task.update",
                    "id": id,
                    "title": current.title,
                    "note": current.note
                ]
            )
            changed()
            return taskPayload(updated)

        case "task.complete", "task.reopen":
            let id = try string(params, "id")
            guard let current = try store.listTasks(includeDone: true).first(where: { $0.id == id }) else {
                throw AgentError.notFound("task \(id)")
            }
            let desired = method == "task.complete"
            if current.done != desired, let updated = try store.toggleTask(id: id) {
                try record(
                    method,
                    payload: ["id": id],
                    undo: ["kind": "task.toggle", "id": id]
                )
                changed()
                return taskPayload(updated)
            }
            return taskPayload(current)

        case "task.delete":
            try requireConfirm(params)
            let id = try string(params, "id")
            guard try store.deleteTask(id: id) else {
                throw AgentError.notFound("task \(id)")
            }
            try record("task.delete", payload: ["id": id], undo: nil)
            changed()
            return ["deleted": id]

        case "project.list":
            let projects = try store.listProjects()
            return [
                "projects": projects.map { project in
                    var payload = projectPayload(project)
                    payload["taskCount"] = (try? store.tasks(projectID: project.id).count) ?? 0
                    return payload
                }
            ]

        case "project.create":
            let name = try string(params, "name")
            let project = try store.createProject(
                name: name,
                description: params["description"] as? String ?? "",
                color: params["color"] as? String ?? "sage"
            )
            try record(
                "project.create",
                payload: ["id": project.id],
                undo: ["kind": "project.delete", "id": project.id]
            )
            changed()
            return projectPayload(project)

        case "project.update":
            let id = try string(params, "id")
            guard let current = try store.listProjects().first(where: { $0.id == id }) else {
                throw AgentError.notFound("project \(id)")
            }
            guard let updated = try store.updateProject(
                id: id,
                name: params["name"] as? String ?? current.name,
                description: params["description"] as? String ?? current.description,
                color: params["color"] as? String ?? current.color
            ) else {
                throw AgentError.notFound("project \(id)")
            }
            try record(
                "project.update",
                payload: ["id": id],
                undo: [
                    "kind": "project.update",
                    "id": id,
                    "name": current.name,
                    "description": current.description,
                    "color": current.color
                ]
            )
            changed()
            return projectPayload(updated)

        case "project.delete":
            try requireConfirm(params)
            let id = try string(params, "id")
            try store.deleteProject(id: id)
            try record("project.delete", payload: ["id": id], undo: nil)
            changed()
            return ["deleted": id]

        case "day.plan":
            let ids = try stringArray(params, "taskIds")
            let dryRun = params["dryRun"] as? Bool ?? false
            let tasks = try store.validateDaySelection(taskIDs: ids)
            let summary: [String: Any] = [
                "dryRun": dryRun,
                "taskIds": tasks.map(\.id),
                "mainCount": tasks.filter { $0.lane == "main" }.count,
                "temporaryCount": tasks.filter { $0.lane == "temporary" }.count
            ]
            if dryRun {
                return summary
            }
            let previous = try store.snapshot().selection
            try store.saveDaySelection(taskIDs: ids)
            try record(
                "day.plan",
                payload: ["taskIds": tasks.map(\.id)],
                undo: ["kind": "day.plan", "taskIds": previous]
            )
            changed()
            return summary

        case "day.start":
            let snapshot = try store.snapshot()
            guard !snapshot.dayStarted else {
                return ["dayStarted": true, "taskCount": snapshot.todayTasks.count]
            }
            guard !snapshot.selection.isEmpty else {
                throw AgentError.invalidParams("今天还没有选择任务")
            }
            try store.startDay(taskIDs: snapshot.selection)
            try record("day.start", payload: ["taskIds": snapshot.selection], undo: nil)
            changed()
            return ["dayStarted": true, "taskCount": snapshot.selection.count]

        case "day.reset":
            try requireConfirm(params)
            let before = try store.snapshot().todayTasks.map(\.id)
            try store.resetDay()
            try record("day.reset", payload: ["taskIds": before], undo: nil)
            changed()
            return ["reset": true]

        case "stats.today":
            let stats = try store.todayStats()
            return [
                "pomodoros": stats.pomodoros,
                "focusSeconds": stats.focusSeconds,
                "completedTasks": stats.completedTasks,
                "records": stats.records.map { record in
                    [
                        "id": record.id,
                        "startedAt": record.startedAt,
                        "durationSec": record.durationSec,
                        "tasks": record.tasks.map {
                            ["id": $0.id, "title": $0.title, "share": $0.share]
                        }
                    ]
                }
            ]

        case "focus.status":
            return try withFocus { try $0.agentFocusStatus() }
        case "focus.start":
            let ids = try stringArray(params, "taskIds")
            return try withFocus { try $0.agentStartFocus(taskIDs: ids) }
        case "focus.pause":
            return try withFocus { try $0.agentPauseFocus() }
        case "focus.resume":
            return try withFocus { try $0.agentResumeFocus() }
        case "focus.stop":
            try requireConfirm(params)
            return try withFocus { try $0.agentStopFocus() }
        case "focus.add":
            let id = try string(params, "taskId")
            return try withFocus { try $0.agentAddFocusTask(taskID: id) }
        case "focus.remove":
            let id = try string(params, "taskId")
            return try withFocus { try $0.agentRemoveFocusTask(taskID: id) }
        case "focus.break":
            return try withFocus { try $0.agentStartBreak() }
        case "focus.skipBreak":
            return try withFocus { try $0.agentSkipBreak() }
        case "focus.next":
            return try withFocus { try $0.agentNextRound() }

        case "agent.events":
            let limit = params["limit"] as? Int ?? 50
            return ["events": try recentEvents(limit: limit)]

        case "agent.undo":
            try requireConfirm(params)
            return try undoLast(params["id"] as? String)

        default:
            throw AgentError.invalidParams("unknown method \(method)")
        }
    }

    private func withFocus(
        _ body: @escaping @Sendable @MainActor (FocusAgentHandling) throws -> [String: Any]
    ) throws -> [String: Any] {
        guard let focus else { throw AgentError.focusUnavailable }
        if Thread.isMainThread {
            let payload = try MainActor.assumeIsolated {
                FocusPayload(value: try body(focus))
            }
            return payload.value
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = FocusResponseBox()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                do {
                    box.result = .success(try body(focus))
                } catch {
                    box.result = .failure(error)
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        switch box.result {
        case let .success(payload): return payload
        case let .failure(error): throw error
        case nil: throw AgentError.focusUnavailable
        }
    }

    private func changed() {
        onChange?()
    }

    private func record(_ action: String, payload: [String: Any], undo: [String: Any]?) throws {
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let payloadText = String(data: payloadData, encoding: .utf8) ?? "{}"
        var undoText: String?
        if let undo {
            let data = try JSONSerialization.data(withJSONObject: undo, options: [.sortedKeys])
            undoText = String(data: data, encoding: .utf8)
        }
        let id = UUID().uuidString
        let at = ISO8601DateFormatter().string(from: Date())
        try store.database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO agent_event (id, at, actor, action, payload, undo)
                VALUES (?, ?, 'agent', ?, ?, ?)
                """,
                arguments: [id, at, action, payloadText, undoText]
            )
        }
    }

    private func recentEvents(limit: Int) throws -> [[String: Any]] {
        try store.database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM agent_event
                ORDER BY at DESC, rowid DESC
                LIMIT ?
                """,
                arguments: [max(1, min(limit, 200))]
            ).map { row in
                [
                    "id": row["id"] as String,
                    "at": row["at"] as String,
                    "actor": row["actor"] as String,
                    "action": row["action"] as String,
                    "payload": row["payload"] as String,
                    "undo": row["undo"] as String? ?? NSNull()
                ]
            }
        }
    }

    private func undoLast(_ id: String?) throws -> [String: Any] {
        let row: Row? = try store.database.queue.read { db in
            let query: String
            let arguments: StatementArguments
            if let id {
                query = "SELECT * FROM agent_event WHERE id = ?"
                arguments = [id]
            } else {
                query = """
                SELECT * FROM agent_event
                WHERE undo IS NOT NULL AND undo != 'undone'
                ORDER BY at DESC, rowid DESC LIMIT 1
                """
                arguments = []
            }
            return try Row.fetchOne(db, sql: query, arguments: arguments)
        }

        guard let row else { throw AgentError.undoUnavailable }
        guard let undoText: String = row["undo"], undoText != "undone",
              let data = undoText.data(using: .utf8),
              let undo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = undo["kind"] as? String else {
            throw AgentError.undoUnavailable
        }

        try applyUndo(kind: kind, object: undo)
        let eventID: String = row["id"]
        try store.database.queue.write { db in
            try db.execute(
                sql: "UPDATE agent_event SET undo = 'undone' WHERE id = ?",
                arguments: [eventID]
            )
        }
        changed()
        return [
            "undone": eventID,
            "action": row["action"] as String
        ]
    }

    private func applyUndo(kind: String, object: [String: Any]) throws {
        switch kind {
        case "task.delete":
            if let id = object["id"] as? String {
                _ = try store.deleteTask(id: id)
            }
        case "task.update":
            if let id = object["id"] as? String,
               let title = object["title"] as? String,
               let note = object["note"] as? String {
                _ = try store.updateTask(id: id, title: title, note: note)
            }
        case "task.toggle":
            if let id = object["id"] as? String {
                _ = try store.toggleTask(id: id)
            }
        case "project.delete":
            if let id = object["id"] as? String {
                try store.deleteProject(id: id)
            }
        case "project.update":
            if let id = object["id"] as? String,
               let name = object["name"] as? String,
               let description = object["description"] as? String,
               let color = object["color"] as? String {
                _ = try store.updateProject(
                    id: id,
                    name: name,
                    description: description,
                    color: color
                )
            }
        case "day.plan":
            if let ids = object["taskIds"] as? [String] {
                if ids.isEmpty {
                    try store.resetDay()
                } else {
                    try store.saveDaySelection(taskIDs: ids)
                }
            }
        default:
            throw AgentError.undoUnavailable
        }
    }

    private func resolveProjectID(_ params: [String: Any]) throws -> String? {
        if let id = params["projectId"] as? String, !id.isEmpty {
            guard try store.listProjects().contains(where: { $0.id == id }) else {
                throw AgentError.notFound("project \(id)")
            }
            return id
        }
        if let name = params["project"] as? String, !name.isEmpty {
            guard let project = try store.listProjects().first(where: { $0.name == name }) else {
                throw AgentError.notFound("project \(name)")
            }
            return project.id
        }
        return nil
    }

    private func resolveDate(_ raw: Any?) -> String? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        return value == "today" ? DayKey.make() : value
    }

    private func taskPayload(_ task: Task) -> [String: Any] {
        var payload: [String: Any] = [
            "id": task.id,
            "title": task.title,
            "lane": task.lane,
            "note": task.note,
            "done": task.done,
            "createdAt": task.createdAt,
            "sortOrder": task.sortOrder
        ]
        if let projectID = task.projectID { payload["projectId"] = projectID }
        if let planned = task.plannedDate { payload["plannedDate"] = planned }
        if let completed = task.completedAt { payload["completedAt"] = completed }
        return payload
    }

    private func projectPayload(_ project: Project) -> [String: Any] {
        [
            "id": project.id,
            "name": project.name,
            "description": project.description,
            "color": project.color,
            "createdAt": project.createdAt,
            "sortOrder": project.sortOrder
        ]
    }

    private func string(_ params: [String: Any], _ key: String) throws -> String {
        guard let value = params[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidParams("缺少 \(key)")
        }
        return value
    }

    private func stringArray(_ params: [String: Any], _ key: String) throws -> [String] {
        guard let value = params[key] as? [String], !value.isEmpty else {
            throw AgentError.invalidParams("缺少 \(key)")
        }
        return value
    }

    private func requireConfirm(_ params: [String: Any]) throws {
        guard params["confirm"] as? Bool == true else {
            throw AgentError.confirmRequired
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

private struct FocusPayload: @unchecked Sendable {
    let value: [String: Any]
}

private final class FocusResponseBox: @unchecked Sendable {
    var result: Result<[String: Any], Error>?
}

public enum ServerError: Error {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case pathTooLong
}
