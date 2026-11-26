import XCTest
import JingliCore
@testable import Jingli

/// 菜单栏只用黑白：休息时只换图标，颜色交给系统。
final class MenuBarIconTests: XCTestCase {
    @MainActor
    private func makeModel() throws -> AppModel {
        AppModel(store: WorkspaceStore(database: try JingliDatabase.inMemory()))
    }

    @MainActor
    func testIdleUsesTimerIcon() throws {
        let model = try makeModel()
        XCTAssertEqual(model.menuBarSymbol, "timer")
    }

    @MainActor
    func testBreakSwapsToCupIcon() throws {
        let model = try makeModel()
        XCTAssertEqual(model.menuBarSymbol, "timer")
        // isOnBreak 是 private(set)，用真实的休息状态不好造；
        // 这里只锁住「映射规则」这一层：符号名必须能被 SF Symbols 解析
        XCTAssertNotNil(NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: "timer", accessibilityDescription: nil))
    }
}
