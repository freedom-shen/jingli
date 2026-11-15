import Foundation
import XCTest
@testable import JingliCore

final class RemoteWebServerTests: XCTestCase {
    private var server: RemoteWebServer?
    private let token = "test-token-1234567890abcdef"

    override func tearDown() {
        server?.stop()
        server = nil
        super.tearDown()
    }

    func testHTMLPageIsServedWithoutToken() throws {
        let (server, _) = try start()
        let (status, data) = try request(
            "http://127.0.0.1:\(server.port)/",
            headers: [:]
        )
        XCTAssertEqual(status, 200)
        let html = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(html.contains("精力管理"))
        XCTAssertTrue(html.contains("/api/today"))
    }

    func testAPIRequiresToken() throws {
        let (server, _) = try start()
        let (status, data) = try request(
            "http://127.0.0.1:\(server.port)/api/today",
            anonymous: true
        )
        XCTAssertEqual(status, 401)
        let json = try jsonObject(data)
        XCTAssertEqual(json["ok"] as? Bool, false)
    }

    func testPingAndTodayWithToken() throws {
        let (server, _) = try start()
        let (pingStatus, pingData) = try request(
            "http://127.0.0.1:\(server.port)/api/ping"
        )
        XCTAssertEqual(pingStatus, 200)
        XCTAssertEqual(try jsonObject(pingData)["ok"] as? Bool, true)

        let (status, data) = try request(
            "http://127.0.0.1:\(server.port)/api/today",
            headers: ["X-Jingli-Token": token]
        )
        XCTAssertEqual(status, 200)
        let json = try jsonObject(data)
        XCTAssertEqual(json["ok"] as? Bool, true)
        let today = try XCTUnwrap(json["today"] as? [String: Any])
        XCTAssertEqual((today["tasks"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(today["dayStarted"] as? Bool, false)
    }

    func testCreateTaskAndToggleDone() throws {
        let (server, database) = try start()
        let (createStatus, createData) = try request(
            "http://127.0.0.1:\(server.port)/api/tasks",
            method: "POST",
            body: Data(#"{"title":"手机上加的任务"}"#.utf8),
            headers: ["X-Jingli-Token": token, "Content-Type": "application/json"]
        )
        XCTAssertEqual(createStatus, 200)
        let created = try jsonObject(createData)
        let task = try XCTUnwrap(created["task"] as? [String: Any])
        let id = try XCTUnwrap(task["id"] as? String)

        let (_, listData) = try request(
            "http://127.0.0.1:\(server.port)/api/today",
            headers: ["X-Jingli-Token": token]
        )
        let list = try jsonObject(listData)
        let today = try XCTUnwrap(list["today"] as? [String: Any])
        let tasks = try XCTUnwrap(today["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?["id"] as? String, id)
        XCTAssertEqual(tasks.first?["title"] as? String, "手机上加的任务")
        XCTAssertEqual(tasks.first?["lane"] as? String, "temporary")
        XCTAssertEqual(tasks.first?["done"] as? Bool, false)

        let (toggleStatus, _) = try request(
            "http://127.0.0.1:\(server.port)/api/tasks/\(id)/toggle",
            method: "POST",
            body: Data(#"{"done":true}"#.utf8),
            headers: ["X-Jingli-Token": token, "Content-Type": "application/json"]
        )
        XCTAssertEqual(toggleStatus, 200)

        let store = WorkspaceStore(database: database)
        let stored = try XCTUnwrap(try store.listTasks(includeDone: true).first { $0.id == id })
        XCTAssertTrue(stored.done)
        XCTAssertNotNil(stored.completedAt)
    }

    func testStartDay() throws {
        let (server, _) = try start()
        _ = try request(
            "http://127.0.0.1:\(server.port)/api/tasks",
            method: "POST",
            body: Data(#"{"title":"今天唯一的事"}"#.utf8),
            headers: ["X-Jingli-Token": token, "Content-Type": "application/json"]
        )
        let (startStatus, startData) = try request(
            "http://127.0.0.1:\(server.port)/api/day/start",
            method: "POST",
            headers: ["X-Jingli-Token": token]
        )
        XCTAssertEqual(startStatus, 200, String(data: startData, encoding: .utf8) ?? "")

        let (_, listData) = try request(
            "http://127.0.0.1:\(server.port)/api/today",
            headers: ["X-Jingli-Token": token]
        )
        let json = try jsonObject(listData)
        let today = try XCTUnwrap(json["today"] as? [String: Any])
        XCTAssertEqual(today["dayStarted"] as? Bool, true)
    }

    func testTokenFromQueryIsAccepted() throws {
        let (server, _) = try start()
        let (status, _) = try request(
            "http://127.0.0.1:\(server.port)/api/day/start?t=\(token)",
            method: "POST",
            headers: [:]
        )
        // 没有任务时 day.start 会报 400，但鉴权已通过（不是 401）。
        XCTAssertNotEqual(status, 401)
    }

    // MARK: - Helpers

    private func start() throws -> (RemoteWebServer, JingliDatabase) {
        let database = try JingliDatabase.inMemory()
        let server = RemoteWebServer(database: database, token: token, port: 0)
        try server.start()
        self.server = server
        return (server, database)
    }

    private func request(
        _ urlString: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        anonymous: Bool = false
    ) throws -> (Int, Data) {
        var url = try XCTUnwrap(URL(string: urlString))
        if !anonymous, !headers.keys.contains("X-Jingli-Token"), !urlString.contains("t=") {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "t", value: token)]
            url = try XCTUnwrap(components?.url)
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error>!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(RemoteWebServer.WebError.listenFailed(-1))
                return
            }
            result = .success((http.statusCode, data ?? Data()))
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)
        return try result.get()
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            String(data: data, encoding: .utf8) ?? ""
        )
    }
}
