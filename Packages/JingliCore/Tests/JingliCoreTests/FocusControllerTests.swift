import XCTest
@testable import JingliCore

final class FocusControllerTests: XCTestCase {
    func testEnableAndDisableCallCorrectShortcuts() throws {
        let runner = MockShortcutRunner()
        runner.available = ["Jingli Focus On", "Jingli Focus Off"]
        let controller = FocusController(runner: runner)

        try controller.enable()
        try controller.disable()

        XCTAssertEqual(runner.ran, ["Jingli Focus On", "Jingli Focus Off"])
        XCTAssertTrue(controller.isConfigured())
    }

    func testMissingShortcutsAreReported() {
        let runner = MockShortcutRunner()
        runner.available = ["Jingli Focus On"]
        let controller = FocusController(runner: runner)

        XCTAssertFalse(controller.isConfigured())
        XCTAssertEqual(controller.missingShortcuts(), ["Jingli Focus Off"])
    }
}

private final class MockShortcutRunner: ShortcutRunning, @unchecked Sendable {
    var available: [String] = []
    var ran: [String] = []

    func run(_ name: String) throws {
        ran.append(name)
    }

    func list() throws -> [String] {
        available
    }
}
