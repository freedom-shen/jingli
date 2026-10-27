import Darwin
import Foundation
import XCTest
@testable import JingliCore

final class AgentServerTests: XCTestCase {
    func testPingPermissionAndConcurrentWrites() throws {
        let database = try JingliDatabase.inMemory()
        let store = WorkspaceStore(database: database)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let socketURL = directory.appendingPathComponent("agent.sock")

        let server = AgentServer(database: database)
        try server.start(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: socketURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)

        let ping = try TestClient(path: socketURL.path).send([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "ping"
        ])
        XCTAssertEqual((ping["result"] as? [String: Any])?["pong"] as? Bool, true)

        let group = DispatchGroup()
        let lock = NSLock()
        var failures: [String] = []

        for index in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let client = try TestClient(path: socketURL.path)
                    let response = try client.send([
                        "jsonrpc": "2.0",
                        "id": index,
                        "method": "task.create",
                        "params": ["title": "task-\(index)"]
                    ])
                    if response["error"] != nil {
                        lock.lock()
                        failures.append("error: \(response)")
                        lock.unlock()
                    }
                } catch {
                    lock.lock()
                    failures.append("\(error)")
                    lock.unlock()
                }
            }
        }

        group.wait()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        XCTAssertEqual(try store.taskCount(), 20)
    }

    func testDestructiveOperationsRequireConfirmAndUndo() throws {
        let database = try JingliDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let socketURL = directory.appendingPathComponent("agent.sock")
        let server = AgentServer(database: database)
        try server.start(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        func call(_ object: [String: Any]) throws -> [String: Any] {
            try TestClient(path: socketURL.path).send(object)
        }

        let created = try call([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "task.create",
            "params": ["title": "待办"]
        ])
        let taskID = (created["result"] as? [String: Any])?["id"] as? String
        XCTAssertNotNil(taskID)

        let denied = try call([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "day.reset"
        ])
        XCTAssertNotNil(denied["error"])

        _ = try call([
            "jsonrpc": "2.0",
            "id": 3,
            "method": "task.complete",
            "params": ["id": taskID ?? ""]
        ])
        let undone = try call([
            "jsonrpc": "2.0",
            "id": 4,
            "method": "agent.undo",
            "params": ["confirm": true]
        ])
        XCTAssertNotNil((undone["result"] as? [String: Any])?["undone"])

        let listed = try call([
            "jsonrpc": "2.0",
            "id": 5,
            "method": "task.list",
            "params": ["includeDone": true]
        ])
        let tasks = (listed["result"] as? [String: Any])?["tasks"] as? [[String: Any]]
        XCTAssertEqual(tasks?.first?["done"] as? Bool, false)
    }

    func testDayAddAppendsToStartedDayAndUndoRemoves() throws {
        let database = try JingliDatabase.inMemory()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let socketURL = directory.appendingPathComponent("agent.sock")
        let server = AgentServer(database: database)
        try server.start(socketURL: socketURL)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        func call(_ object: [String: Any]) throws -> [String: Any] {
            try TestClient(path: socketURL.path).send(object)
        }

        let first = try call([
            "jsonrpc": "2.0", "id": 1,
            "method": "task.create", "params": ["title": "主线A", "lane": "main"]
        ])
        let firstID = (first["result"] as? [String: Any])?["id"] as? String
        _ = try call([
            "jsonrpc": "2.0", "id": 2,
            "method": "day.plan", "params": ["taskIds": [firstID ?? ""]]
        ])
        let started = try call(["jsonrpc": "2.0", "id": 3, "method": "day.start"])
        XCTAssertNotNil((started["result"] as? [String: Any])?["dayStarted"])

        let second = try call([
            "jsonrpc": "2.0", "id": 4,
            "method": "task.create", "params": ["title": "主线B", "lane": "main"]
        ])
        let secondID = (second["result"] as? [String: Any])?["id"] as? String

        let added = try call([
            "jsonrpc": "2.0", "id": 5,
            "method": "day.add", "params": ["taskIds": [secondID ?? ""]]
        ])
        let addedList = (added["result"] as? [String: Any])?["added"] as? [[String: Any]]
        XCTAssertEqual(addedList?.first?["id"] as? String, secondID)

        let today = try call(["jsonrpc": "2.0", "id": 6, "method": "today"])
        let todayTasks = (today["result"] as? [String: Any])?["tasks"] as? [[String: Any]]
        XCTAssertEqual(todayTasks?.count, 2)

        _ = try call([
            "jsonrpc": "2.0", "id": 7,
            "method": "agent.undo", "params": ["confirm": true]
        ])
        let afterUndo = try call(["jsonrpc": "2.0", "id": 8, "method": "today"])
        let undoTasks = (afterUndo["result"] as? [String: Any])?["tasks"] as? [[String: Any]]
        XCTAssertEqual(undoTasks?.count, 1)

        let extras = try (0..<4).map { index -> String in
            let created = try call([
                "jsonrpc": "2.0", "id": 10 + index,
                "method": "task.create", "params": ["title": "主线-\(index)", "lane": "main"]
            ])
            return (created["result"] as? [String: Any])?["id"] as? String ?? ""
        }
        let overflow = try call([
            "jsonrpc": "2.0", "id": 20,
            "method": "day.add", "params": ["taskIds": extras]
        ])
        XCTAssertNotNil(overflow["error"])
    }
}

private final class TestClient {
    private let fd: Int32

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.socket(errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw ClientError.pathTooLong
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
            throw ClientError.connect(code)
        }
    }

    deinit {
        close(fd)
    }

    func send(_ object: [String: Any]) throws -> [String: Any] {
        var payload = try JSONSerialization.data(withJSONObject: object)
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
        guard wrote else { throw ClientError.writeFailed }

        var response = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count <= 0 { break }
            if byte == 0x0A { break }
            response.append(byte)
        }
        guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        return object
    }
}

private enum ClientError: Error {
    case socket(Int32)
    case connect(Int32)
    case pathTooLong
    case writeFailed
    case invalidResponse
}
