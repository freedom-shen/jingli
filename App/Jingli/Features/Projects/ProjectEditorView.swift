import SwiftUI
import JingliCore

struct ProjectEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let project: Project?
    private let colors = ["sage", "amber", "blue", "rose", "violet", "slate"]

    @State private var name: String
    @State private var description: String
    @State private var color: String
    @State private var showDeleteConfirm = false

    init(model: AppModel, project: Project?) {
        self.model = model
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _description = State(initialValue: project?.description ?? "")
        _color = State(initialValue: project?.color ?? "sage")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(project == nil ? "新建项目" : "编辑项目")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("项目名称")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("这个项目叫什么？", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.card)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("项目描述（选填）")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                TextField("你想通过这个项目，做到什么？", text: $description)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.card)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("项目颜色")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    ForEach(colors, id: \.self) { item in
                        Button {
                            color = item
                        } label: {
                            Circle()
                                .fill(Theme.projectColor(item))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            color == item ? Theme.textPrimary : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if project != nil {
                    Button("删除项目", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.red.opacity(0.85))
                }

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)

                Button("保存") {
                    let saved = model.saveProject(
                        name: name,
                        description: description,
                        color: color,
                        projectID: project?.id
                    )
                    if saved { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.textPrimary)
                .foregroundStyle(Theme.background)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "删除这个项目？",
            isPresented: $showDeleteConfirm
        ) {
            Button("删除项目", role: .destructive) {
                if let project {
                    model.deleteProject(project)
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("项目里的任务会保留，并移到「未分类任务」。")
        }
    }
}
