import SwiftUI
import JingliCore

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var lane: String
    @State private var projectID = ""
    @State private var estimate: Int?
    private let fixedLane: String?

    init(
        model: AppModel,
        defaultProjectID: String? = nil,
        fixedLane: String? = nil
    ) {
        self.model = model
        self.fixedLane = fixedLane
        _lane = State(initialValue: fixedLane ?? "main")
        _projectID = State(initialValue: defaultProjectID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(fixedLane == "temporary" ? "新建临时任务" : "新建任务")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if fixedLane == "temporary" {
                    Text("临时任务直接进入今天，不占 4 件主线名额。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务名称")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("接下来，想完成什么？", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.card)
                    )
                    .accessibilityIdentifier("task-title-field")
            }

            if fixedLane == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("任务标签")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("任务标签", selection: $lane) {
                        Text("主线任务").tag("main")
                        Text("临时任务").tag("temporary")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("所属项目")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                Picker("所属项目", selection: $projectID) {
                    Text("无项目").tag("")
                    ForEach(model.projects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("预计番茄")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    estimateStepper
                    Text(estimate.map { "≈ \($0 * 25) 分钟" } ?? "不填就是估不出来")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("创建") {
                    let created = model.createTask(
                        title: title,
                        lane: lane,
                        projectID: projectID.isEmpty ? nil : projectID,
                        estimate: estimate
                    )
                    if created { dismiss() }
                }
                .buttonStyle(CompactPrimaryButtonStyle())
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("create-task-button")
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var estimateStepper: some View {
        HStack(spacing: 0) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)

            Text(estimate.map(String.init) ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 26)
                .foregroundStyle(estimate == nil ? Theme.textSecondary : Theme.textPrimary)

            Button {
                step(1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.textSecondary)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(height: 26)
        .accessibilityIdentifier("task-estimate-stepper")
    }

    private func step(_ delta: Int) {
        guard let current = estimate else {
            if delta > 0 { estimate = 1 }
            return
        }
        let next = current + delta
        estimate = next < 1 ? nil : min(32, next)
    }
}
