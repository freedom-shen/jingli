import XCTest
@testable import JingliCore

final class FocusCreditTests: XCTestCase {
    func testSingleParticipant() {
        XCTAssertEqual(FocusCredit.shares(participants: 1), [1.0])
    }

    func testSharedParticipants() {
        XCTAssertEqual(FocusCredit.shares(participants: 2), [0.5, 0.5])
        XCTAssertEqual(FocusCredit.shares(participants: 4), [0.25, 0.25, 0.25, 0.25])
    }

    func testThreeWaySum() {
        let shares = FocusCredit.shares(participants: 3)
        XCTAssertEqual(shares.count, 3)
        XCTAssertEqual(shares.reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testNoParticipants() {
        XCTAssertTrue(FocusCredit.shares(participants: 0).isEmpty)
    }

    func testDisplayRounding() {
        let total = 1.0 / 3.0 + 1.0 / 3.0 + 1.0 / 3.0
        XCTAssertEqual(FocusCredit.roundedForDisplay(total), 1.0)
        XCTAssertEqual(FocusCredit.roundedForDisplay(0.3333), 0.33)
    }
}
