import AppKit
import XCTest
import JingliCore
@testable import Jingli

/// 菜单栏那块的颜色映射：MenuBarExtra 的 label 不吃颜色，所以颜色逻辑单独测。
final class MenuBarLookTests: XCTestCase {

    func testFocusingIsLabelColoredTimer() {
        let look = MenuBarLook.make(for: .focusing)
        XCTAssertEqual(look.symbolName, "timer")
        XCTAssertEqual(look.color, .labelColor)
        XCTAssertEqual(look.colorName, "label")
    }

    func testIdleLooksLikeFocusing() {
        XCTAssertEqual(MenuBarLook.make(for: .idle), MenuBarLook.make(for: .focusing))
    }

    func testPausedDimsTheTimer() {
        let look = MenuBarLook.make(for: .paused)
        XCTAssertEqual(look.symbolName, "timer")
        XCTAssertEqual(look.color, .secondaryLabelColor)
        XCTAssertEqual(look.colorName, "secondary")
    }

    func testBreakTurnsTheWholeItemGreen() {
        let look = MenuBarLook.make(for: .onBreak)
        XCTAssertEqual(look.symbolName, "cup.and.saucer")
        XCTAssertEqual(look.color, MenuBarLook.breakGreen)
        XCTAssertEqual(look.colorName, "break-green")

        // 绿要真的是绿：G 明显高于 R 和 B，别配成灰或偏蓝
        let rgb = look.color.usingColorSpace(.sRGB)!
        XCTAssertGreaterThan(rgb.greenComponent, rgb.redComponent + 0.1)
        XCTAssertGreaterThan(rgb.greenComponent, rgb.blueComponent + 0.05)
    }

    @MainActor
    func testStateFollowsModelFlags() throws {
        let database = try JingliDatabase.inMemory()
        let model = AppModel(store: WorkspaceStore(database: database))
        XCTAssertEqual(model.menuBarState, MenuBarState.idle)
    }

    func testRenderedImageIsNotTemplateAndNotEmpty() {
        for state in [MenuBarState.idle, .focusing, .paused, .onBreak] {
            let image = MenuBarLabelImage.make(text: "24:00", state: state)
            XCTAssertFalse(image.isTemplate, "\(state) 的图必须保留颜色")
            XCTAssertGreaterThan(image.size.width, 20)
            XCTAssertGreaterThan(image.size.height, 8)
        }
    }
}
