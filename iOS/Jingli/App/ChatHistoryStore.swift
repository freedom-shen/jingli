import Foundation
import JingliCore

/// 助手聊天记录存本地（App Group 里一个 JSON）。
/// 只留角色、文字、用到的工具名 —— 足够还原界面，也不至于把参数和结果全堆上来。
enum ChatHistoryStore {
    struct Item: Codable {
        let role: String
        let text: String
        let tools: [Tool]
        let at: Date
    }

    struct Tool: Codable {
        let name: String
        let ok: Bool
    }

    private static let limit = 120

    private static var fileURL: URL {
        AppPaths.supportDirectory.appendingPathComponent("chat-history.json")
    }

    static func load() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([Item].self, from: data)
        else { return [] }
        return items
    }

    static func save(_ items: [Item]) {
        let trimmed = items.suffix(limit)
        guard let data = try? JSONEncoder().encode(Array(trimmed)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
