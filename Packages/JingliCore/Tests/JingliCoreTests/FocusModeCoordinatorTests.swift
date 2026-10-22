import XCTest
@testable import JingliCore

final class FocusModeCoordinatorTests: XCTestCase {
    func testBeginEnablesWhenNoFocusAndOwnsIt() throws {
        let runner = RecordingShortcutRunner(available: ["Jingli Focus On", "Jingli Focus Off"])
        let coordinator = FocusModeCoordinator(
            controller: FocusController(runner: runner),
            status: StubFocusStatus(value: false)
        )

        XCTAssertEqual(coordinator.begin(), .enabled)
        XCTAssertTrue(coordinator.isOwned)
        waitUntil { runner.ran == ["Jingli Focus On"] }

        coordinator.end()
        XCTAssertFalse(coordinator.isOwned)
        waitUntil { runner.ran == ["Jingli Focus On", "Jingli Focus Off"] }
    }

    func testBeginKeepsExistingFocusUntouched() throws {
        let runner = RecordingShortcutRunner(available: ["Jingli Focus On", "Jingli Focus Off"])
        let coordinator = FocusModeCoordinator(
            controller: FocusController(runner: runner),
            status: StubFocusStatus(value: true)
        )

        XCTAssertEqual(coordinator.begin(), .alreadyFocused)
        XCTAssertFalse(coordinator.isOwned)
        coordinator.end()

        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(runner.ran.isEmpty)
    }

    func testBeginReportsUnavailableWhenShortcutsMissing() throws {
        let runner = RecordingShortcutRunner(available: [])
        let coordinator = FocusModeCoordinator(
            controller: FocusController(runner: runner),
            status: StubFocusStatus(value: false)
        )

        XCTAssertEqual(coordinator.begin(), .unavailable)
        XCTAssertFalse(coordinator.isOwned)
    }

    func testUnknownFocusStatusTreatedAsOff() throws {
        let runner = RecordingShortcutRunner(available: ["Jingli Focus On", "Jingli Focus Off"])
        let coordinator = FocusModeCoordinator(
            controller: FocusController(runner: runner),
            status: StubFocusStatus(value: nil)
        )

        XCTAssertEqual(coordinator.begin(), .enabled)
        waitUntil { runner.ran == ["Jingli Focus On"] }
    }

    func testRestoreAssumesOwnership() throws {
        let runner = RecordingShortcutRunner(available: ["Jingli Focus On", "Jingli Focus Off"])
        let coordinator = FocusModeCoordinator(
            controller: FocusController(runner: runner),
            status: StubFocusStatus(value: true)
        )

        coordinator.restore()
        XCTAssertTrue(coordinator.isOwned)
        waitUntil { runner.ran == ["Jingli Focus On"] }

        coordinator.end()
        waitUntil { runner.ran == ["Jingli Focus On", "Jingli Focus Off"] }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("condition not met within \(timeout)s", file: file, line: line)
    }
}

private struct StubFocusStatus: FocusStatusReading {
    let value: Bool?

    func isFocused() -> Bool? { value }
}

private final class RecordingShortcutRunner: ShortcutRunning, @unchecked Sendable {
    let available: [String]
    private let lock = NSLock()
    private var storage: [String] = []

    init(available: [String]) {
        self.available = available
    }

    var ran: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func run(_ name: String) throws {
        lock.lock()
        storage.append(name)
        lock.unlock()
    }

    func list() throws -> [String] {
        available
    }
}
