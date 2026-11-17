import XCTest
@testable import JingliCore
import JingliSync

final class SyncEngineTests: XCTestCase {
    private struct Device {
        let database: JingliDatabase
        let store: WorkspaceStore
        let sync: SyncStore
        let engine: SyncEngine
    }

    private func makeDevice(_ transport: FakeTransport) throws -> Device {
        let database = try JingliDatabase.inMemory()
        let sync = SyncStore(database: database)
        return Device(
            database: database,
            store: WorkspaceStore(database: database),
            sync: sync,
            engine: SyncEngine(store: sync, transport: transport)
        )
    }

    func testTwoDevicesConvergeThroughTransport() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)

        let pa = try a.store.createProject(name: "共享项目")
        _ = try a.store.createTask(title: "A 建的任务", projectID: pa.id, lane: "main")
        _ = try b.store.createTask(title: "B 建的任务", lane: "temporary")

        let reportA = try await a.engine.syncOnce()
        XCTAssertGreaterThan(reportA.pushed, 0)

        let _ = try await b.engine.syncOnce()
        let _ = try await a.engine.syncOnce()

        let titlesA = Set(try a.store.listTasks().map(\.title))
        let titlesB = Set(try b.store.listTasks().map(\.title))
        XCTAssertEqual(titlesA, titlesB, "两端应看到同一批任务")
        XCTAssertTrue(titlesA.contains("A 建的任务"))
        XCTAssertTrue(titlesA.contains("B 建的任务"))
    }

    func testSecondSyncIsNoOp() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)
        _ = try a.store.createTask(title: "一条", lane: "temporary")

        let _ = try await a.engine.syncOnce()
        let _ = try await b.engine.syncOnce()
        let again = try await b.engine.syncOnce()

        XCTAssertEqual(again.pushed, 0, "没有新写入就不该重复推")
        XCTAssertEqual(again.pulled, 0, "游标之后没有新变更")
    }

    func testPendingChangesSurviveTransportFailure() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        _ = try a.store.createTask(title: "推不出去", lane: "temporary")
        await transport.setFailNextPush(true)

        do {
            let _ = try await a.engine.syncOnce()
            XCTFail("传输失败应该抛出来")
        } catch {
            XCTAssertGreaterThan(try a.sync.pendingCount(), 0, "失败的变更要留着下次再推")
        }
    }
}
