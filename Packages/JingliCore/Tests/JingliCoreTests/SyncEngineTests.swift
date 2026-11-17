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

// MARK: - 多设备离线场景

extension SyncEngineTests {
    func testConcurrentEditsOnDifferentFieldsBothSurvive() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)

        let task = try a.store.createTask(title: "初始标题", lane: "temporary", plannedDate: nil)
        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()

        // 两端各自离线修改不同字段
        _ = try a.store.updateTask(id: task.id, title: "A 改的标题", note: "", estimate: 3)
        _ = try b.store.updateTask(id: task.id, title: "初始标题", note: "B 加的备注", estimate: 5)

        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()
        _ = try await a.engine.syncOnce()

        let onA = try XCTUnwrap(try a.store.listTasks(includeDone: true).first { $0.id == task.id })
        let onB = try XCTUnwrap(try b.store.listTasks(includeDone: true).first { $0.id == task.id })
        XCTAssertEqual(onA.title, "A 改的标题")
        XCTAssertEqual(onA.note, "B 加的备注", "不同字段应该都保留")
        XCTAssertEqual(onA.estimate, 5)
        XCTAssertEqual(onA.title, onB.title)
        XCTAssertEqual(onA.note, onB.note)
    }

    func testConcurrentEditOnSameFieldConverges() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)

        let task = try a.store.createTask(title: "原名", lane: "temporary", plannedDate: nil)
        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()

        _ = try a.store.updateTask(id: task.id, title: "A 写的", note: "", estimate: nil)
        _ = try b.store.updateTask(id: task.id, title: "B 写的", note: "", estimate: nil)

        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()
        _ = try await a.engine.syncOnce()

        let onA = try XCTUnwrap(try a.store.listTasks(includeDone: true).first { $0.id == task.id })
        let onB = try XCTUnwrap(try b.store.listTasks(includeDone: true).first { $0.id == task.id })
        XCTAssertEqual(onA.title, onB.title, "同一字段冲突后两端必须一致")
        XCTAssertTrue(["A 写的", "B 写的"].contains(onA.title))
    }

    func testDeleteDuringOfflinePropagates() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)

        let task = try a.store.createTask(title: "会被删掉", lane: "temporary", plannedDate: nil)
        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()
        XCTAssertEqual(try b.store.listTasks(includeDone: true).count, 1)

        _ = try a.store.deleteTask(id: task.id)
        _ = try await a.engine.syncOnce()
        _ = try await b.engine.syncOnce()

        XCTAssertTrue(
            try b.store.listTasks(includeDone: true).isEmpty,
            "删除应传播到对端，不能因为离线而被“复活”"
        )
    }
}

// MARK: - 失败重试

extension SyncEngineTests {
    func testFailedSyncRetriesAutomatically() async throws {
        let transport = FakeTransport()
        let a = try makeDevice(transport)
        let b = try makeDevice(transport)
        _ = try a.store.createTask(title: "网络抖动时写的", lane: "temporary")

        let service = SyncService(
            store: a.sync,
            engine: a.engine,
            debounceSeconds: 0,
            retryBaseSeconds: 0.05
        )
        await transport.setFailNextPush(true)
        let failed = await service.syncNow()
        XCTAssertNotNil(failed.lastError, "第一次应该失败")
        XCTAssertGreaterThan(failed.pending, 0, "变更必须留着")

        // 等退避重试把剩下的推上去
        try? await _Concurrency.Task.sleep(nanoseconds: 600_000_000)
        let recovered = await service.status()
        XCTAssertNil(recovered.lastError, "重试成功后错误应清掉")
        XCTAssertEqual(recovered.pending, 0)

        _ = try await b.engine.syncOnce()
        XCTAssertTrue(
            try b.store.listTasks(includeDone: true).contains { $0.title == "网络抖动时写的" },
            "重试推上去的变更对端应该能收到"
        )
    }
}
