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

guard let command = arguments.first else {
    fail("usage: jingli ping | task add <title> | task count")
}

var request: [String: Any] = ["jsonrpc": "2.0", "id": 1]

switch command {
case "ping":
    request["method"] = "ping"
case "task":
    guard arguments.count >= 2 else {
        fail("usage: jingli task add <title> | task count")
    }
    switch arguments[1] {
    case "add":
        let title = arguments.dropFirst(2).joined(separator: " ")
        guard !title.isEmpty else { fail("usage: jingli task add <title>") }
        request["method"] = "task.create"
        request["params"] = ["title": title]
    case "count":
        request["method"] = "task.count"
    default:
        fail("unknown task command: \(arguments[1])")
    }
default:
    fail("unknown command: \(command)")
}

do {
    let response = try send(request, to: socketPath)
    let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8) ?? "{}")
    if response["error"] != nil {
        exit(1)
    }
} catch {
    fail("cannot reach \(socketPath): \(error)")
}
