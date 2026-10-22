import Darwin
import Foundation
import JingliCore

enum CLIError: Error {
    case usage
    case socket(Int32)
    case connect(Int32)
    case pathTooLong
    case writeFailed
    case emptyResponse
    case invalidResponse
}

func fail(_ message: String) -> Never {
    fputs("jingli: \(message)\n", stderr)
    exit(1)
}

func connect(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CLIError.socket(errno) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        close(fd)
        throw CLIError.pathTooLong
    }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        bytes.withUnsafeBytes { source in
            raw.copyBytes(from: source)
        }
    }

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        let code = errno
        close(fd)
        throw CLIError.connect(code)
    }
    return fd
}

func send(_ request: [String: Any], to path: String) throws -> [String: Any] {
    let fd = try connect(path: path)
    defer { close(fd) }

    var payload = try JSONSerialization.data(withJSONObject: request)
    payload.append(0x0A)
    let wrote = payload.withUnsafeBytes { raw -> Bool in
        guard let base = raw.baseAddress else { return false }
        var offset = 0
        while offset < raw.count {
            let count = write(fd, base.advanced(by: offset), raw.count - offset)
            if count <= 0 { return false }
            offset += count
        }
        return true
    }
    guard wrote else { throw CLIError.writeFailed }

    var response = Data()
    var byte: UInt8 = 0
    while true {
        let count = read(fd, &byte, 1)
        if count <= 0 { break }
        if byte == 0x0A { break }
        response.append(byte)
    }
    guard !response.isEmpty else { throw CLIError.emptyResponse }
    guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
        throw CLIError.invalidResponse
    }
    return object
}

let environment = ProcessInfo.processInfo.environment
let socketPath = environment["JINGLI_SOCKET"] ?? AppPaths.socketURL.path
let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: name),
          args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
}

func hasFlag(_ name: String, in args: [String]) -> Bool {
    args.contains(name)
}

func positional(_ args: [String], skipping flags: Set<String>) -> [String] {
    var result: [String] = []
    var index = 0
    while index < args.count {
        let value = args[index]
        if value.hasPrefix("--") {
            if flags.contains(value) {
                index += 2
            } else {
                index += 1
            }
            continue
        }
        result.append(value)
        index += 1
    }
    return result
}

let flags: Set<String> = [
    "--project", "--lane", "--date", "--title", "--note",
    "--description", "--color", "--confirm"
]

func request(method: String, params: [String: Any] = [:]) -> [String: Any] {
    var payload: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": method]
    if !params.isEmpty {
        payload["params"] = params
    }

    do {
        return try send(payload, to: socketPath)
    } catch {
        guard environment["JINGLI_SOCKET"] == nil else {
            fail("无法连接 \(socketPath): \(error)")
        }
        try? launchApp()
        for _ in 0..<40 {
            if let response = try? send(payload, to: socketPath) {
                return response
            }
            usleep(250_000)
        }
        fail("App 未运行，且自动启动超时；请先打开「精力管理」")
    }
}

func launchApp() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", "com.freedom-shen.jingli"]
    try process.run()
    process.waitUntilExit()
}

func run(_ method: String, params: [String: Any] = [:]) -> Never {
    let response = request(method: method, params: params)
    let output = (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]))
        ?? Data()
    print(String(data: output, encoding: .utf8) ?? "{}")
    exit(response["error"] == nil ? 0 : 1)
}

guard let command = arguments.first else {
    fail("""
    usage:
      jingli today
      jingli task add <title> [--project 名称] [--lane main|temporary] [--date today]
      jingli task list [--all]
      jingli task update <id> [--title 标题] [--note 备注]
      jingli task complete|reopen <id>
      jingli task delete <id> --confirm
      jingli project list
      jingli project add <name> [--description 描述] [--color sage]
      jingli project update <id> [--name 名称] [--description 描述] [--color sage]
      jingli project delete <id> --confirm
      jingli day plan <id...> [--dry-run]
      jingli day start
      jingli day reset --confirm
      jingli focus start <id...>
      jingli focus status|pause|resume
      jingli focus stop --confirm
      jingli focus add|remove <id>
      jingli stats
      jingli events [--limit 50]
      jingli undo [id] --confirm
    """)
}

let rest = Array(arguments.dropFirst())

switch command {
case "ping":
    run("ping")
case "today":
    run("today")
case "stats":
    run("stats.today")
case "events":
    let limit = Int(option("--limit", in: rest) ?? "50") ?? 50
    run("agent.events", params: ["limit": limit])
case "undo":
    let id = rest.first { !$0.hasPrefix("--") }
    run("agent.undo", params: ["confirm": hasFlag("--confirm", in: rest), "id": id ?? NSNull()])
case "task":
    guard let sub = rest.first else { fail("task add|list|update|complete|reopen|delete") }
    let tail = Array(rest.dropFirst())
    let words = positional(tail, skipping: flags)
    switch sub {
    case "add":
        guard let title = words.first else { fail("task add <title>") }
        var params: [String: Any] = ["title": title]
        if let project = option("--project", in: tail) { params["project"] = project }
        if let lane = option("--lane", in: tail) { params["lane"] = lane }
        if let date = option("--date", in: tail) { params["date"] = date }
        run("task.create", params: params)
    case "list":
        run("task.list", params: ["includeDone": hasFlag("--all", in: tail)])
    case "count":
        run("task.count")
    case "update":
        guard let id = words.first else { fail("task update <id>") }
        var params: [String: Any] = ["id": id]
        if let title = option("--title", in: tail) { params["title"] = title }
        if let note = option("--note", in: tail) { params["note"] = note }
        run("task.update", params: params)
    case "complete", "done":
        guard let id = words.first else { fail("task complete <id>") }
        run("task.complete", params: ["id": id])
    case "reopen":
        guard let id = words.first else { fail("task reopen <id>") }
        run("task.reopen", params: ["id": id])
    case "delete":
        guard let id = words.first else { fail("task delete <id>") }
        run("task.delete", params: ["id": id, "confirm": hasFlag("--confirm", in: tail)])
    default:
        fail("unknown task command: \(sub)")
    }
case "project":
    guard let sub = rest.first else { fail("project list|add|update|delete") }
    let tail = Array(rest.dropFirst())
    let words = positional(tail, skipping: flags)
    switch sub {
    case "list":
        run("project.list")
    case "add":
        guard let name = words.first else { fail("project add <name>") }
        var params: [String: Any] = ["name": name]
        if let description = option("--description", in: tail) {
            params["description"] = description
        }
        if let color = option("--color", in: tail) { params["color"] = color }
        run("project.create", params: params)
    case "update":
        guard let id = words.first else { fail("project update <id>") }
        var params: [String: Any] = ["id": id]
        if let name = option("--name", in: tail) { params["name"] = name }
        if let description = option("--description", in: tail) {
            params["description"] = description
        }
        if let color = option("--color", in: tail) { params["color"] = color }
        run("project.update", params: params)
    case "delete":
        guard let id = words.first else { fail("project delete <id>") }
        run("project.delete", params: ["id": id, "confirm": hasFlag("--confirm", in: tail)])
    default:
        fail("unknown project command: \(sub)")
    }
case "day":
    guard let sub = rest.first else { fail("day plan|start|reset") }
    let tail = Array(rest.dropFirst())
    switch sub {
    case "plan":
        let ids = positional(tail, skipping: flags)
        guard !ids.isEmpty else { fail("day plan <id...>") }
        run("day.plan", params: [
            "taskIds": ids,
            "dryRun": hasFlag("--dry-run", in: tail)
        ])
    case "start":
        run("day.start")
    case "reset":
        run("day.reset", params: ["confirm": hasFlag("--confirm", in: tail)])
    default:
        fail("unknown day command: \(sub)")
    }
case "focus":
    guard let sub = rest.first else { fail("focus start|status|pause|resume|stop|add|remove") }
    let tail = Array(rest.dropFirst())
    let words = positional(tail, skipping: flags)
    switch sub {
    case "start":
        guard !words.isEmpty else { fail("focus start <id...>") }
        run("focus.start", params: ["taskIds": words])
    case "status":
        run("focus.status")
    case "pause":
        run("focus.pause")
    case "resume":
        run("focus.resume")
    case "stop":
        run("focus.stop", params: ["confirm": hasFlag("--confirm", in: tail)])
    case "add", "remove":
        guard let id = words.first else { fail("focus \(sub) <id>") }
        run(sub == "add" ? "focus.add" : "focus.remove", params: ["taskId": id])
    case "break":
        run("focus.break")
    case "skip-break":
        run("focus.skipBreak")
    case "next":
        run("focus.next")
    default:
        fail("unknown focus command: \(sub)")
    }
default:
    fail("unknown command: \(command)")
}
