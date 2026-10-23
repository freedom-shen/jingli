import SwiftUI
import JingliCore

struct TaskEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var lane: String
    @State private var projectID = ""
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

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("创建") {
                    let created = model.createTask(
                        title: title,
                        lane: lane,
                        projectID: projectID.isEmpty ? nil : projectID
                    )
                    if created { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.textPrimary)
                .foregroundStyle(Theme.background)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("create-task-button")
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}
