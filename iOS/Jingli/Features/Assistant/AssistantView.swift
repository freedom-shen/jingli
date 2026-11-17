import SwiftUI
import JingliCore
import JingliAgent

struct AssistantView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// 从统计页带过来的问题，放在输入框里等用户确认，不自动发。
    var prefill: String?
    @State private var draft = ""
    @State private var transcriber = SpeechTranscriber()

    private let suggestions = ["今天还剩几件", "把评审设计稿加进今天，两个番茄", "昨天专注了多久"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if !model.assistantReady { keyHint }
                            if model.chat.isEmpty { intro }
                            ForEach(model.chat) { item in
                                bubble(item)
                            }
                            if model.assistantBusy { thinking }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: model.chat.count) {
                        if let last = model.chat.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                inputBar
            }
            .background(Tokens.bg)
            .navigationTitle("助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(model.llmConfig.model)
                        .font(.system(size: 10))
                        .foregroundStyle(Tokens.text3)
                        .lineLimit(1)
                        .frame(maxWidth: 92, alignment: .leading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.foregroundStyle(Tokens.text3)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: transcriber.transcript) { _, value in
            if transcriber.isRecording { draft = value }
        }
        .task {
            if let prefill, draft.isEmpty { draft = prefill }
            let args = CommandLine.arguments
            if args.contains("-voice") {
                await transcriber.start()
            }
            if let raw = args.first(where: { $0.hasPrefix("-ask=") }) {
                await model.send(String(raw.dropFirst("-ask=".count)))
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("说一句话，我去改今天的计划")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
            Text("「把评审设计稿加进今天，两个番茄」「今天还剩几件」——每一处改动都会落成一张卡片，可以看、可以撤。")
                .font(.system(size: 12)).foregroundStyle(Tokens.text3)
            FlowChips(items: suggestions) { text in
                _Concurrency.Task { await model.send(text) }
            }
        }
        .padding(.top, 16)
    }

    private var keyHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "key").font(.system(size: 11)).foregroundStyle(Tokens.accent)
            Text("还没配置模型，去「设置 → 助手」填 Key").font(.system(size: 11)).foregroundStyle(Tokens.text3)
            Spacer()
        }
        .padding(11)
        .background(Tokens.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Tokens.accent.opacity(0.18)))
    }

    @ViewBuilder
    private func bubble(_ item: IOSAppModel.ChatItem) -> some View {
        switch item.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Tokens.text)
                    .padding(.horizontal, 13).padding(.vertical, 10)
                    .background(Tokens.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.accent.opacity(0.28)))
            }
            .id(item.id)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Tokens.text)
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
                }
                if !item.tools.isEmpty { toolCard(item.tools) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(item.id)
        }
    }

    private func toolCard(_ tools: [ExecutedTool]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: tools.allSatisfy(\.ok) ? "checkmark" : "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .bold))
                Text("已执行 \(tools.count) 个操作").font(.system(size: 10.5))
                Spacer()
            }
            .foregroundStyle(tools.allSatisfy(\.ok) ? Tokens.accent : Tokens.tomato)

            ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                Text("· \(tool.name)\(tool.ok ? "" : "（失败）")")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.text3)
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Tokens.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.accent.opacity(0.24)))
    }

    private var thinking: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("在想…").font(.system(size: 11)).foregroundStyle(Tokens.text3)
        }
        .padding(.top, 4)
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let error = transcriber.errorText {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Tokens.tomato)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text("说点什么…").foregroundStyle(Tokens.text3))
                .font(.system(size: 13.5))
                .foregroundStyle(Tokens.text)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Tokens.card, in: Capsule())
                .overlay(Capsule().stroke(Tokens.line))
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                _Concurrency.Task { await toggleVoice() }
            } label: {
                Image(systemName: transcriber.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(transcriber.isRecording ? Tokens.tomato : Tokens.text2)
                    .frame(width: 36, height: 36)
                    .background(
                        (transcriber.isRecording ? Tokens.tomato : Color.white).opacity(0.10),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("assistant.mic")

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                    .frame(width: 36, height: 36)
                    .background(draft.isEmpty ? Tokens.accent.opacity(0.35) : Tokens.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("assistant.send")
            .disabled(draft.isEmpty || model.assistantBusy)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Tokens.bg)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.line).frame(height: 1) }
    }

    private func toggleVoice() async {
        if transcriber.isRecording {
            transcriber.stop()
            if !transcriber.transcript.isEmpty { draft = transcriber.transcript }
        } else {
            draft = ""
            await transcriber.start()
        }
    }

    private func send() {
        let text = draft
        draft = ""
        _Concurrency.Task { await model.send(text) }
    }
}

private struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Tokens.text2)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Color.white.opacity(0.05), in: Capsule())
                        .overlay(Capsule().stroke(Tokens.line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
