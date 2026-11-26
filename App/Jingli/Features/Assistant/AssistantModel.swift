import AppKit
import Foundation
import ImageIO
import JingliAgent
import JingliCore

/// Mac 端助手的会话状态：调模型、执行工具、把图压好挂进待发送区。
///
/// 工具和 iOS 那套是同一份 `ToolCatalog` / `AgentCommandRouter`，所以这边能做的事
/// 和 CLI、`jingli` Skill 完全一致；这里只负责「把一句话和图送过去、把结果摆出来」。
@MainActor
final class AssistantModel: ObservableObject {
    struct ChatItem: Identifiable {
        enum Role: String { case user, assistant }
        let id: UUID
        let role: Role
        let text: String
        let images: [ImageAttachment]
        let tools: [ExecutedTool]
        let at: Date

        init(
            id: UUID = UUID(),
            role: Role,
            text: String,
            images: [ImageAttachment] = [],
            tools: [ExecutedTool] = [],
            at: Date = Date()
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.images = images
            self.tools = tools
            self.at = at
        }
    }

    /// 一次最多贴几张，和设计稿一致。
    static let maxImages = 4

    @Published private(set) var chat: [ChatItem] = []
    @Published private(set) var busy = false
    @Published private(set) var attachments: [ImageAttachment] = []
    @Published var config: LLMConfig
    @Published var notice: String?

    /// 全 App 一份：设置页清空会话时清的是同一个实例。
    static let shared = AssistantModel()

    private let database: JingliDatabase
    private let historyURL: URL
    private let onChange: @MainActor () -> Void

    init(
        database: JingliDatabase? = nil,
        config: LLMConfig? = nil,
        historyURL: URL = AssistantHistoryStore.defaultURL,
        onChange: (@MainActor () -> Void)? = nil
    ) {
        self.database = database ?? AppServices.shared.database
        self.config = config ?? LLMConfigStore.fromEnvironment() ?? LLMConfigStore.load()
        self.historyURL = historyURL
        self.onChange = onChange ?? {
            AppServices.shared.model.reload()
            AppServices.shared.model.refreshStats()
        }
        chat = Self.restore(from: AssistantHistoryStore.load(from: historyURL))
    }

    // MARK: - 配置

    var ready: Bool { config.isReady }

    func updateConfig(_ next: LLMConfig) {
        config = next
        LLMConfigStore.save(next)
        notice = nil
    }

    /// 用一句最短的话试一下，验证服务地址 / Key / 模型名是否能通。
    func testConnection() async -> String {
        guard let provider = config.makeProvider() else { return "还没填完：服务地址、模型名、API Key 都要有" }
        do {
            let reply = try await provider.complete(
                messages: [.user("ping，只回一个 ok")],
                tools: []
            )
            let text = (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "连上了，但模型没回内容" : "连上了：\(text.prefix(40))"
        } catch {
            return "连不上：\(error.localizedDescription)"
        }
    }

    // MARK: - 图片

    var canAddAttachment: Bool { attachments.count < Self.maxImages }

    func addImage(data: Data) {
        guard canAddAttachment else {
            notice = "一次最多 \(Self.maxImages) 张，先发这一轮吧"
            return
        }
        do {
            attachments.append(try ImagePreparer.prepare(data: data))
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func addImage(contentsOf url: URL) {
        guard canAddAttachment else {
            notice = "一次最多 \(Self.maxImages) 张，先发这一轮吧"
            return
        }
        do {
            attachments.append(try ImagePreparer.prepare(contentsOf: url))
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }

    func removeAttachment(_ id: ImageAttachment.ID) {
        attachments.removeAll { $0.id == id }
        notice = nil
    }

    func clearAttachments() {
        attachments.removeAll()
        notice = nil
    }

    /// ⌘V：优先取图片，其次取文件；文本粘贴不归这里管。
    @discardableResult
    func pasteFromPasteboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard let data = Self.imageData(from: pasteboard) else {
            notice = "剪贴板里没有图片"
            return false
        }
        addImage(data: data)
        return true
    }

    private static func imageData(from pasteboard: NSPasteboard) -> Data? {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .pdf]
        for type in types {
            if let data = pasteboard.data(forType: type) { return data }
        }
        // 从 Finder 拖 / 复制进来的文件
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            for url in urls {
                if let data = try? Data(contentsOf: url) { return data }
            }
        }
        // 截图工具常放的是 NSImage
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
            return tiff
        }
        return nil
    }

    // MARK: - 对话

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachments
        guard !trimmed.isEmpty || !images.isEmpty, !busy else { return }

        chat.append(ChatItem(role: .user, text: trimmed, images: images))
        attachments.removeAll()
        notice = nil
        persist()

        guard let provider = config.makeProvider() else {
            chat.append(ChatItem(
                role: .assistant,
                text: "还没有配模型：右上角齿轮里填服务地址、模型名和 API Key。"
            ))
            persist()
            return
        }

        busy = true
        let database = self.database
        let onChange = self.onChange
        _Concurrency.Task { [weak self] in
            let router = AgentCommandRouter(database: database, focus: nil, onChange: nil, actor: "mac-agent")
            let agent = JingliAgent(provider: provider, runner: ToolRunner(router: router))
            do {
                let reply = try await agent.send(trimmed, images: images)
                self?.chat.append(ChatItem(role: .assistant, text: reply.text, tools: reply.toolCalls))
                self?.busy = false
                self?.persist()
                if !reply.toolCalls.isEmpty { onChange() }
            } catch {
                self?.chat.append(ChatItem(
                    role: .assistant,
                    text: "出错了：\(error.localizedDescription)"
                ))
                self?.busy = false
                self?.persist()
            }
        }
    }

    /// 截图基线用：摆一段固定的对话，不碰网络。
    func seedSnapshotConversation() {
        let image = Self.snapshotImage().flatMap { try? ImagePreparer.prepare(data: $0) }
        let at = Self.snapshotNow
        chat = [
            ChatItem(role: .assistant, text: "早。今天主线 2 件、临时 1 件；截图直接 ⌘V 贴进来就能问。", at: at),
            ChatItem(
                role: .user,
                text: "这个自定义组件调试页白屏了，看图能定位吗？",
                images: image.map { [$0] } ?? [],
                at: at
            ),
            ChatItem(
                role: .assistant,
                text: "截图里只有一片白和转圈，没有报错栈，不像代码崩了。更像容器拿到了空快照：调试模块没注册，或者 h5 资源没拉下来。",
                at: at
            ),
            ChatItem(
                role: .assistant,
                text: "",
                tools: [ExecutedTool(name: "today_get", argumentsJSON: "{}", ok: true, output: "2 件主线")],
                at: at
            ),
        ]
    }

    /// 截图基线要可复现：跟着 JINGLI_FAKE_NOW_MS 走，否则卡片上的时间每次都变。
    private static var snapshotNow: Date {
        if let raw = ProcessInfo.processInfo.environment["JINGLI_FAKE_NOW_MS"],
           let value = Double(raw) {
            return Date(timeIntervalSince1970: value / 1000)
        }
        return Date()
    }

    /// 画一张「白屏截图」，给基线用，尺寸和内容都固定。
    private static func snapshotImage() -> Data? {
        let width = 640
        let height = 360
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.14, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 26, width: width, height: 26))
        context.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
        context.setLineWidth(6)
        context.strokeEllipse(in: CGRect(x: width / 2 - 26, y: height / 2 - 26, width: 52, height: 52))

        guard let cgImage = context.makeImage() else { return nil }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    func clearChat() {
        chat.removeAll()
        attachments.removeAll()
        notice = nil
        AssistantHistoryStore.clear(at: historyURL)
    }

    /// 设置页显示用：现在存了多少条、占多大。
    var storedHistoryCount: Int { chat.count }
    var storedHistoryBytes: Int { AssistantHistoryStore.byteCount(at: historyURL) }

    private func persist() {
        AssistantHistoryStore.save(chat.map(Self.item), to: historyURL)
    }

    private static func item(_ chat: ChatItem) -> AssistantHistoryItem {
        AssistantHistoryItem(
            id: chat.id,
            role: chat.role.rawValue,
            text: chat.text,
            tools: chat.tools.map { .init(name: $0.name, ok: $0.ok) },
            images: chat.images.map(AssistantHistoryStore.stored(from:)),
            at: chat.at
        )
    }

    private static func restore(from items: [AssistantHistoryItem]) -> [ChatItem] {
        items.map { item in
            ChatItem(
                id: item.id,
                role: item.role == "user" ? .user : .assistant,
                text: item.text,
                images: item.images.map(AssistantHistoryStore.attachment(from:)),
                tools: item.tools.map {
                    ExecutedTool(name: $0.name, argumentsJSON: "", ok: $0.ok, output: "")
                },
                at: item.at
            )
        }
    }
}
