import XCTest
@testable import JingliCore

final class TaskOrderTests: XCTestCase {
    func testFallbackOrderWhenNoManualOrder() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let b = try store.createTask(title: "B", lane: "temporary")

        let ordered = try store.orderedTasks(scope: "today:x:temporary", fallback: [a, b])
        XCTAssertEqual(ordered.map(\.id), [a.id, b.id])
    }

    func testSavedOrderWins() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let b = try store.createTask(title: "B", lane: "temporary")
        let c = try store.createTask(title: "C", lane: "temporary")

        try store.saveTaskOrder(
            scope: "today:x:temporary",
            orderedIDs: [c.id, a.id, b.id]
        )

        let ordered = try store.orderedTasks(
            scope: "today:x:temporary",
            fallback: [a, b, c]
        )
        XCTAssertEqual(ordered.map(\.id), [c.id, a.id, b.id])
    }

    func testTasksWithoutOrderAppendInFallbackOrder() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let b = try store.createTask(title: "B", lane: "temporary")
        let late = try store.createTask(title: "晚到", lane: "temporary")

        try store.saveTaskOrder(
            scope: "today:x:temporary",
            orderedIDs: [b.id, a.id]
        )

        let ordered = try store.orderedTasks(
            scope: "today:x:temporary",
            fallback: [a, b, late]
        )
        XCTAssertEqual(ordered.map(\.id), [b.id, a.id, late.id])
    }

    func testScopesAreIsolated() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let b = try store.createTask(title: "B", lane: "temporary")

        try store.saveTaskOrder(
            scope: "today:x:temporary",
            orderedIDs: [b.id, a.id]
        )

        let mainScope = try store.orderedTasks(
            scope: "today:x:main",
            fallback: [a, b]
        )
        XCTAssertEqual(mainScope.map(\.id), [a.id, b.id])
    }

    func testTodayScopePrunesOtherDays() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let project = try store.createProject(name: "工作")
        let p = try store.createTask(title: "P", projectID: project.id)

        try store.saveTaskOrder(scope: "today:2026-10-26:temporary", orderedIDs: [a.id])
        try store.saveTaskOrder(scope: "project:\(project.id)", orderedIDs: [p.id])
        try store.saveTaskOrder(scope: "today:2026-10-27:temporary", orderedIDs: [a.id])

        let leftoverTodayScopes = try store.database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task_order WHERE scope LIKE 'today:%'"
            )
        }
        let projectScopes = try store.database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT scope) FROM task_order WHERE scope LIKE 'project:%'"
            )
        }
        XCTAssertEqual(leftoverTodayScopes, 1)
        XCTAssertEqual(projectScopes, 1)
    }

    func testRewriteScope() throws {
        let store = try makeStore()
        let a = try store.createTask(title: "A", lane: "temporary")
        let b = try store.createTask(title: "B", lane: "temporary")

        try store.saveTaskOrder(scope: "today:x:temporary", orderedIDs: [b.id, a.id])
        try store.saveTaskOrder(scope: "today:x:temporary", orderedIDs: [a.id, b.id])

        let ordered = try store.orderedTasks(scope: "today:x:temporary", fallback: [b, a])
        XCTAssertEqual(ordered.map(\.id), [a.id, b.id])
    }

    private func makeStore() throws -> WorkspaceStore {
        try WorkspaceStore(database: JingliDatabase.inMemory())
    }
}
