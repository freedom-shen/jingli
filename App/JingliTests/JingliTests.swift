import AppKit
import SwiftUI
import XCTest
import JingliCore
@testable import Jingli

@MainActor
final class JingliTests: XCTestCase {
    func testFloatingPanelVisibilityToggleInBothModes() {
        let controller = FloatingPanelController.shared
        controller.hide()
        defer { controller.hide() }

        XCTAssertFalse(controller.isVisible)
        controller.toggleVisibility()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.mode, .mini)
        controller.toggleVisibility()
        XCTAssertFalse(controller.isVisible)

        controller.toggleVisibility()
        controller.setMode(.standard)
        XCTAssertTrue(controller.isVisible)
        controller.toggleVisibility()
        XCTAssertFalse(controller.isVisible)
        controller.toggleVisibility()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.mode, .mini)
        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }

    func testFloatingPanelCollapsesOnlyForOutsideClicksWhileExpanded() {
        XCTAssertTrue(FloatingPanelConfiguration.shouldCollapse(mode: .standard, clickInside: false))
        XCTAssertFalse(FloatingPanelConfiguration.shouldCollapse(mode: .standard, clickInside: true))
        XCTAssertFalse(FloatingPanelConfiguration.shouldCollapse(mode: .mini, clickInside: false))
        XCTAssertFalse(FloatingPanelConfiguration.shouldCollapse(mode: .mini, clickInside: true))
    }

    func testProjectCompletionTracksTasksAndPreservesGroupOrder() throws {
        let store = WorkspaceStore(database: try JingliDatabase.inMemory())
        let empty = try store.createProject(name: "Empty")
        let mixed = try store.createProject(name: "Mixed")
        let finished = try store.createProject(name: "Finished")
        let first = try store.createTask(title: "First", projectID: mixed.id)
        _ = try store.createTask(title: "Second", projectID: mixed.id)
        let last = try store.createTask(title: "Last", projectID: finished.id)
        _ = try store.toggleTask(id: first.id)
        _ = try store.toggleTask(id: last.id)
        let model = AppModel(store: store)

        XCTAssertEqual(model.finishedProjects.map(\.id), [finished.id])
        XCTAssertEqual(model.activeProjects.map(\.id), model.projects.filter { $0.id != finished.id }.map(\.id))
        XCTAssertTrue(model.activeProjects.contains { $0.id == empty.id })

        model.toggleDone(last)
        XCTAssertTrue(model.finishedProjects.isEmpty)
        model.toggleDone(last)
        XCTAssertEqual(model.finishedProjects.map(\.id), [finished.id])

        let added = try store.createTask(title: "New", projectID: finished.id)
        model.reload()
        XCTAssertTrue(model.finishedProjects.isEmpty)
        model.toggleDone(added)
        XCTAssertEqual(model.finishedProjects.map(\.id), [finished.id])
    }

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
