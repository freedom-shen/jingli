import AppKit
import SwiftUI
import JingliAgent
import JingliCore

/// Mac 端助手页：左边对话、右边「今天」，底部输入区支持 ⌘V 贴图。
struct AssistantView: View {
    @ObservedObject var model: AssistantModel
    @ObservedObject var app: AppModel

    @State private var draft = ""
    @State private var showModelConfig = false
    @State private var isDropping = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 30) {
            chatColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            rail
                .frame(width: 320)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 22)
        .background(Theme.background)
        .sheet(isPresented: $showModelConfig) {
            ModelConfigSheet(model: model)
        }
        // 进页面就把光标放进输入框：等一次 run loop，输入框才真正在响应链上
        .task { focusInputSoon() }
        .onChange(of: app.page) { _, page in
            guard page == .assistant else { return }
            focusInputSoon()
        }
    }

    /// 截图基线里不要光标闪烁，否则同一份代码两次渲染会对不上。
    private var isSnapshotRun: Bool { CommandLine.arguments.contains("--snapshot") }

    private func focusInputSoon() {
        guard !isSnapshotRun else { return }
        _Concurrency.Task {
            try? await _Concurrency.Task.sleep(for: .milliseconds(60))
            inputFocused = true
        }
    }

    // MARK: - 左：对话

    private var chatColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.chat.isEmpty { intro }
                        ForEach(model.chat) { item in
                            bubble(item).id(item.id)
                        }
                        if model.busy { thinking }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .onChange(of: model.chat.count) {
                    guard let last = model.chat.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            composer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(todaySummary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(model.ready ? Color(red: 0.37, green: 0.75, blue: 0.49) : Theme.textSecondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(model.ready ? "\(providerName) · \(model.config.model)" : "还没配模型")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.card.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.07)))
            .accessibilityIdentifier("assistant-model-status")

            Button {
                showModelConfig = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .help("模型配置")
            .accessibilityLabel("模型配置")
            .accessibilityIdentifier("assistant-model-settings")
        }
    }

    private var todaySummary: String {
        let tasks = app.snapshot?.todayTasks ?? []
        let main = tasks.filter { $0.lane == "main" }.count
        let temp = tasks.count - main
        return "今天 · \(main) 件主线 · \(temp) 件临时"
    }

    private var providerName: String {
        if let host = URL(string: model.config.baseURL)?.host {
            return host
        }
        return "模型"
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说一句话，我去改今天的计划")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("「把评审设计稿加进今天，两个番茄」「今天还剩几件」——每一处改动都会落成一张卡片，可以看、可以撤。白屏、报错这类截图，直接 ⌘V 贴进来问。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func bubble(_ item: AssistantModel.ChatItem) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 7) {
                    ForEach(item.images) { image in
                        if let data = image.data, let picture = NSImage(data: data) {
                            Image(nsImage: picture)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1)))
                        }
                    }
                    if !item.text.isEmpty {
                        Text(item.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Color(red: 0.90, green: 0.93, blue: 0.98))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.28)))
                    }
                }
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07)))
                }
                if !item.tools.isEmpty { toolCard(item.tools, at: item.at) }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private func toolCard(_ tools: [ExecutedTool], at: Date) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: tools.allSatisfy(\.ok) ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 9.5, weight: .bold))
                Text("已执行 \(tools.count) 个操作").font(.system(size: 11))
                Spacer()
            }
            .foregroundStyle(tools.allSatisfy(\.ok) ? Theme.accent : Theme.tomato)

            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                Text("· \(tool.name)\(tool.ok ? "" : "（失败）")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 14) {
                Text("结果已写进今天的计划").font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                Spacer()
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07)))
    }

    private var thinking: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("在想…").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - 输入区

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !model.attachments.isEmpty { attachmentRow }

            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tomato)
            }

            HStack(spacing: 9) {
                Button(action: chooseFiles) {
                    Image(systemName: "paperclip").font(.system(size: 13)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("选图片")
                .accessibilityLabel("选图片")
                .accessibilityIdentifier("assistant-attach")

                Button {
                    model.pasteFromPasteboard()
                } label: {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 12.5)).frame(width: 26, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("粘贴图片（⌘V）")
                .accessibilityLabel("粘贴图片")
                .accessibilityIdentifier("assistant-paste-image")

                TextField("", text: $draft, prompt: Text("说点什么，或者把截图贴进来…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.card, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.08)))
                    .accessibilityIdentifier("assistant-input")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        .frame(width: 32, height: 32)
                        .background(canSend ? Theme.accent : Theme.accent.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend || model.busy)
                .accessibilityLabel("发送")
                .accessibilityIdentifier("assistant-send")
            }
        }
        .padding(10)
        .background(Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDropping ? Theme.accent.opacity(0.6) : Color.white.opacity(0.09))
        )
        .onPasteCommand(of: [.png, .tiff, .fileURL]) { _ in
            model.pasteFromPasteboard()
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropping) { providers in
            handleDrop(providers)
        }
        .overlay(alignment: .bottomLeading) {
            Text("⌘V 粘贴图片 · 拖文件进窗口也行 · 单张上限 10 MB，超了先压到 1024 px")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.55))
                .padding(.leading, 4)
                .offset(y: 16)
        }
        .padding(.bottom, 8)
    }

    private var attachmentRow: some View {
        HStack(spacing: 8) {
            ForEach(model.attachments) { image in
                ZStack(alignment: .topTrailing) {
                    if let data = image.data, let picture = NSImage(data: data) {
                        Image(nsImage: picture)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.12)))
                    }
                    Button {
                        model.removeAttachment(image.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Color.black.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .accessibilityLabel("移除这张图")
                }
            }
            Spacer()
            Text("\(model.attachments.count) / \(AssistantModel.maxImages) 张")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.8))
        }
        .padding(.horizontal, 2)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.attachments.isEmpty
    }

    private func send() {
        guard canSend, !model.busy else { return }
        let text = draft
        draft = ""
        model.send(text)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.addImage(contentsOf: url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                _Concurrency.Task { @MainActor in model.addImage(contentsOf: url) }
            }
        }
        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                guard let tiff = (image as? NSImage)?.tiffRepresentation else { return }
                _Concurrency.Task { @MainActor in model.addImage(data: tiff) }
            }
        }
        return true
    }

    // MARK: - 右：今天 / 模型

    private var rail: some View {
        VStack(spacing: 14) {
            todayPanel
            modelPanel
            Spacer()
        }
        .padding(.top, 2)
    }

    private var todayPanel: some View {
        let tasks = app.snapshot?.todayTasks ?? []
        let main = tasks.filter { $0.lane == "main" }
        let temporary = tasks.filter { $0.lane != "main" }

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("今天").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(DayKey.make().suffix(5)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(.bottom, 12)

            groupLabel("主线", "\(main.count) / 4")
            ForEach(main) { task in
                row(task)
            }
            if main.isEmpty {
                emptyRow("还没开始一天")
            }

            groupLabel("临时", "\(temporary.count) 件")
            ForEach(temporary) { task in
                row(task)
            }
            if temporary.isEmpty {
                emptyRow("今天还没有临时任务")
            }

            HStack {
                Text("今日番茄 \(app.todayPomodoroCount) 个")
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.textSecondary.opacity(0.8))
            .padding(.top, 12)
        }
        .padding(16)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07)))
    }

    private func groupLabel(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.textSecondary.opacity(0.75))
            Spacer()
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(_ task: JingliCore.Task) -> some View {
        HStack(spacing: 8) {
            Text(task.title)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary.opacity(0.86))
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Circle()
                    .fill(task.estimate == nil ? Color.white.opacity(0.18) : Theme.tomato)
                    .frame(width: 6, height: 6)
                Text(task.estimate.map(String.init) ?? "未估")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1) }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary.opacity(0.6))
            .padding(.vertical, 6)
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("模型").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(model.ready ? "已连上" : "未配置")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary.opacity(0.8))
            }
            .padding(.bottom, 10)

            kv("服务", URL(string: model.config.baseURL)?.host ?? "—")
            kv("模型", model.config.model.isEmpty ? "—" : model.config.model)
            kv("图片", "支持 · 一次最多 \(AssistantModel.maxImages) 张")
            kv("Key", model.config.apiKey.isEmpty ? "未填" : "系统 Keychain")

            Text("只把你输入的那句话、贴进来的图和工具结果发给这个服务；任务库本身不上传。")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(16)
        .background(Theme.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.07)))
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary.opacity(0.75))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary.opacity(0.86))
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}
