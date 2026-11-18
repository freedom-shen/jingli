import SwiftUI
import JingliCore

/// 新建任务：打字路径。语音录入在 M4 接进来，这里只保证字段和规则完整。
struct AddTaskView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// 从项目详情进来时，类型和项目都锁到这个项目上
    var presetProjectID: String?
    var presetProjectName: String?
    /// 快捷指令 / 深链带过来的标题，打开就已填好
    var presetTitle: String?

    @State private var title = ""
    @State private var lane = "temporary"
    @State private var projectID: String?
    @State private var estimate: Int?
    @State private var note = ""
    @State private var errorText: String?
    @State private var transcriber = SpeechTranscriber()

    private var projects: [Project] {
        model.projectGroups.compactMap(\.project)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        presetProjectID: String? = nil,
        presetProjectName: String? = nil,
        presetTitle: String? = nil
    ) {
        self.presetProjectID = presetProjectID
        self.presetProjectName = presetProjectName
        self.presetTitle = presetTitle
        _lane = State(initialValue: presetProjectID == nil ? "temporary" : "main")
        _projectID = State(initialValue: presetProjectID)
        _title = State(initialValue: presetTitle ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    ruleCard
                    metaCard
                    noteCard
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Tokens.tomato)
                            .padding(.horizontal, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(Tokens.bg)
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Tokens.text3)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("addtask.save")
                        .foregroundStyle(canSave ? Tokens.accent : Tokens.text3)
                        .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var titleField: some View {
        HStack(spacing: 10) {
            TextField("", text: $title, prompt: Text("要做什么？").foregroundStyle(Tokens.text3))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Tokens.text)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)

            // 语音录入：录一段，标题就是你说的话
            Button {
                _Concurrency.Task { await toggleVoice() }
            } label: {
                Image(systemName: transcriber.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(transcriber.isRecording ? Tokens.tomato : Tokens.text2)
                    .frame(width: 32, height: 32)
                    .background(
                        (transcriber.isRecording ? Tokens.tomato : Color.white).opacity(0.10),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("addtask.mic")
        }
        .padding(14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
        .onChange(of: transcriber.transcript) { _, value in
            if transcriber.isRecording { title = value }
        }
    }

    private func toggleVoice() async {
        if transcriber.isRecording {
            transcriber.stop()
        } else {
            await transcriber.start()
        }
    }

    private var ruleCard: some View {
        HStack(spacing: 7) {
            Image(systemName: lane == "temporary" ? "bolt.fill" : "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(lane == "temporary" ? Tokens.accent : Tokens.green)
            Text(lane == "temporary"
                 ? "临时任务：不限量，保存后直接进今天"
                 : "主线任务：属于项目，占今天 4 件名额")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.text3)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var metaCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("类型").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                Spacer()
                HStack(spacing: 3) {
                    segment("临时", active: lane == "temporary") { lane = "temporary"; projectID = nil }
                    segment("主线", active: lane == "main") { lane = "main" }
                }
                .padding(3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(.vertical, 12)

            Divider().overlay(Tokens.line)

            HStack {
                Text("项目").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                Spacer()
                Menu {
                    Button("未分类") { projectID = nil }
                    ForEach(projects) { project in
                        Button(project.name) { projectID = project.id; lane = "main" }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(projects.first { $0.id == projectID }?.name ?? "未分类")
                            .font(.system(size: 13))
                            .foregroundStyle(lane == "temporary" ? Tokens.text3 : Tokens.text2)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Tokens.text3)
                    }
                }
                .disabled(lane == "temporary")
            }
            .padding(.vertical, 12)

            Divider().overlay(Tokens.line)

            HStack {
                Text("预估").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                Spacer()
                HStack(spacing: 12) {
                    Button { adjust(-1) } label: {
                        Image(systemName: "minus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tokens.text2)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("减少预估")
                    if let estimate {
                        Text("\(estimate)")
                            .font(.system(size: 15, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Tokens.text)
                            .frame(minWidth: 22)
                    } else {
                        Text("未估")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Tokens.text3)
                            .frame(minWidth: 22)
                    }
                    Button { adjust(1) } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tokens.text2)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel("增加预估")
                    Text("个番茄").font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
                }
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("备注").font(.system(size: 13)).foregroundStyle(Tokens.text3)
            TextField("", text: $note, prompt: Text("复现步骤、验收标准…"), axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(Tokens.text)
                .lineLimit(3...6)
        }
        .padding(14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private func segment(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: active ? .medium : .regular))
                .foregroundStyle(active ? Color(red: 0.78, green: 0.84, blue: 0.95) : Tokens.text3)
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(active ? Tokens.accent.opacity(0.22) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ delta: Int) {
        let current = estimate ?? 0
        let next = max(0, min(32, current + delta))
        estimate = next == 0 ? nil : next
    }

    private func save() {
        do {
            let task = try model.createTask(
                title: title,
                projectID: lane == "main" ? projectID : nil,
                lane: lane,
                estimate: estimate,
                note: note
            )
            if lane == "temporary" {
                try model.addToToday(taskIDs: [task.id])
            }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
