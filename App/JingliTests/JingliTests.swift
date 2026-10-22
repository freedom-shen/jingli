import AppKit
import SwiftUI
import XCTest
@testable import Jingli

@MainActor
final class JingliTests: XCTestCase {
    func testAppTargetLoads() {
        XCTAssertTrue(true)
    }

    func testPanelConfiguration() {
        XCTAssertEqual(FloatingPanelConfiguration.level, .screenSaver)
        XCTAssertTrue(
            FloatingPanelConfiguration.collectionBehavior.contains(.canJoinAllSpaces)
        )
        XCTAssertTrue(
            FloatingPanelConfiguration.collectionBehavior.contains(.fullScreenAuxiliary)
        )
        XCTAssertTrue(
            FloatingPanelConfiguration.collectionBehavior.contains(.ignoresCycle)
        )
    }

    func testFirstMouseViewAcceptsFirstMouse() {
        let view = FirstMouseHostingView(rootView: Text("test"))
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }
}
