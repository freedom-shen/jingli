import Darwin
import Foundation
import GRDB

/// JSON-RPC 命令处理：Unix socket（AgentServer）和远程网页（RemoteWebServer）共用。
///
/// 业务默认走 `WorkspaceStore`，破坏性操作要求 `confirm`，写操作会记入 `agent_event`。
/// `actor` 只影响审计日志里的来源（agent / web）。
public final class AgentCommandRouter: @unchecked Sendable {
    private let store: WorkspaceStore
    private let focus: FocusAgentHandling?
    private let onChange: (@Sendable () -> Void)?
    private let actor: String

    public init(
        database: JingliDatabase,
        focus: FocusAgentHandling? = nil,
        onChange: (@Sendable () -> Void)? = nil,
        actor: String = "agent"
    ) {
        self.store = WorkspaceStore(database: database)
        self.focus = focus
        self.onChange = onChange
        self.actor = actor
    }

    public func process(line: String) -> String {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = object["method"] as? String else {
            return errorResponse(id: NSNull(), code: -32700, message: "parse error")
        }

        let id = object["id"] ?? NSNull()
        let params = object["params"] as? [String: Any] ?? [:]

        do {
            let result = try call(method: method, params: params)
            let response: [String: Any] = ["jsonrpc": "2.0", "id": id, "result": result]
            let data = try JSONSerialization.data(withJSONObject: response)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return errorResponse(id: id, code: -32000, message: "\(error.localizedDescription)")
        }
    }

    /// 统一命令入口：Unix socket 的 JSON-RPC 和网页 API 都走这里。
    public func call(method: String, params: [String: Any] = [:]) throws -> Any {
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
            let undated = params["undated"] as? Bool ?? false
            let plannedDate = undated
                ? nil
                : (resolveDate(params["date"])
                    ?? (lane == "temporary" ? DayKey.make() : nil))
            let task = try store.createTask(
                title: title,
                projectID: projectID,
                lane: lane,
                plannedDate: plannedDate,
                estimate: (params["estimate"] as? NSNumber)?.intValue
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
            let estimate: Int?
            if let raw = params["estimate"] {
                estimate = (raw as? NSNumber)?.intValue
            } else {
                estimate = current.estimate
            }
            guard let updated = try store.updateTask(
                id: id,
                title: title,
                note: note,
                estimate: estimate
            ) else {
                throw AgentError.notFound("task \(id)")
            }
            try record(
                "task.update",
                payload: ["id": id],
                undo: Self.taskUndoPayload(current)
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

        /// 今天（含已开始）追加已有任务：项目主线占 4 件空位，临时任务直接进。
        case "day.add":
            let ids = try stringArray(params, "taskIds")
            guard !ids.isEmpty else { throw AgentError.invalidParams("day add 需要至少一个任务 id") }
            let added = try store.addToToday(taskIDs: ids)
            let addedIDs = added.map(\.id)
            try record(
                "day.add",
                payload: ["taskIds": addedIDs],
                undo: addedIDs.isEmpty ? nil : ["kind": "day.add", "taskIds": addedIDs]
            )
            changed()
            return [
                "added": added.map { ["id": $0.id, "title": $0.title, "lane": $0.lane] },
                "mainRemaining": max(0, 4 - (try store.plannedMainCount()))
            ]

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
                "records": stats.records.map(recordPayload)
            ]

        case "stats.history":
            let days = params["days"] as? Int ?? (params["date"] != nil ? 1 : 7)
            let endingOn = params["date"] as? String ?? DayKey.make()
            let history = try store.history(days: days, endingOn: endingOn)
            return [
                "days": history.map { day -> [String: Any] in
                    [
                        "date": day.date,
                        "pomodoros": day.pomodoros,
                        "focusSeconds": day.focusSeconds,
                        "completedTasks": day.completedTasks.map { task -> [String: Any] in
                            var payload: [String: Any] = [
                                "id": task.id,
                                "title": task.title,
                                "completedAt": task.completedAt
                            ]
                            if let projectID = task.projectID {
                                payload["projectId"] = projectID
                            }
                            return payload
                        },
                        "records": day.records.map(recordPayload)
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
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [id, at, actor, action, payloadText, undoText]
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
                _ = try store.updateTask(
                    id: id,
                    title: title,
                    note: note,
                    estimate: (object["estimate"] as? NSNumber)?.intValue
                )
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
        case "day.add":
            if let ids = object["taskIds"] as? [String] {
                let today = DayKey.make()
                try store.database.queue.write { db in
                    for id in ids {
                        try db.execute(
                            sql: "UPDATE task SET planned_date = NULL WHERE id = ? AND planned_date = ?",
                            arguments: [id, today]
                        )
                        try db.execute(
                            sql: "DELETE FROM day_plan_task WHERE date = ? AND task_id = ?",
                            arguments: [today, id]
                        )
                    }
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

    private func recordPayload(_ record: FocusRecord) -> [String: Any] {
        [
            "id": record.id,
            "startedAt": record.startedAt,
            "durationSec": record.durationSec,
            "tasks": record.tasks.map {
                ["id": $0.id, "title": $0.title, "share": $0.share]
            }
        ]
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
        if let estimate = task.estimate { payload["estimate"] = estimate }
        return payload
    }

    private static func taskUndoPayload(_ task: Task) -> [String: Any] {
        var payload: [String: Any] = [
            "kind": "task.update",
            "id": task.id,
            "title": task.title,
            "note": task.note
        ]
        if let estimate = task.estimate {
            payload["estimate"] = estimate
        }
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
}

private struct FocusPayload: @unchecked Sendable {
    let value: [String: Any]
}

private final class FocusResponseBox: @unchecked Sendable {
    var result: Result<[String: Any], Error>?
}
