import SwiftUI
import JingliCore

/// 「+」添加今日任务：左 Tab 从已有任务抽取，右 Tab 新建。
/// 无项目 = 临时任务；选了项目 = 项目任务（占主线名额）。
struct AddTaskView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String {
        case existing
        case create
    }

    @State private var tab: Tab = .existing
    @State private var search = ""
    @State private var newTitle = ""
    @State private var newProjectID = ""

    private var trimmedTitle: String {
        newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var creatingMain: Bool {
        !newProjectID.isEmpty
    }

    private var mainBlocked: Bool {
        creatingMain && model.mainSlotsRemaining == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("添加今日任务")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("从已有任务里挑一件，或者新建一条临时任务。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            tabBar

            Group {
                switch tab {
                case .existing:
                    existingPane
                case .create:
                    createPane
                }
            }
            .frame(minHeight: 250)

            HStack(alignment: .center) {
                Text(footHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)

                if tab == .create {
                    Button("创建") {
                        if model.addNewTaskToToday(
                            title: trimmedTitle,
                            projectID: newProjectID.isEmpty ? nil : newProjectID
                        ) {
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.textPrimary)
                    .foregroundStyle(Theme.background)
                    .disabled(trimmedTitle.isEmpty || mainBlocked)
                    .accessibilityIdentifier("add-task-create-button")
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private var footHint: String {
        switch tab {
        case .existing:
            return "点任务加入今天并关闭 · 不是复制"
        case .create:
            return mainBlocked
                ? "主线名额已满，先完成或移除一件"
                : (creatingMain ? "项目任务加入今天的主线" : "无项目 = 今天的临时任务")
        }
    }

    // MARK: - Tab 栏

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("已有任务", tab: .existing, identifier: "add-task-tab-existing")
            tabButton("新建", tab: .create, identifier: "add-task-tab-create")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func tabButton(
        _ title: String,
        tab target: Tab,
        identifier: String
    ) -> some View {
        Button {
            tab = target
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == target ? .semibold : .regular))
                .foregroundStyle(tab == target ? Theme.textPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tab == target ? Theme.accent.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 已有任务

    private var filteredGroups: [AddTaskPickerGroup] {
        let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return model.addTaskPickerGroups() }
        return model.addTaskPickerGroups().map { group in
            AddTaskPickerGroup(
                id: group.id,
                title: group.title,
                color: group.color,
                tasks: group.tasks.filter {
                    $0.title.localizedCaseInsensitiveContains(keyword)
                }
            )
        }.filter { !$0.tasks.isEmpty }
    }

    private var existingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                TextField("搜索任务…", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .accessibilityIdentifier("add-task-search")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.card)
            )

            let groups = filteredGroups
            if groups.isEmpty {
                Spacer()
                Text(search.isEmpty ? "没有可添加的任务" : "没有匹配「\(search)」的任务")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                }
            }
        }
    }

    private func section(_ group: AddTaskPickerGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let color = group.color {
                    Circle()
                        .fill(Theme.projectColor(color))
                        .frame(width: 6, height: 6)
                }
                Text("\(group.title) · \(group.tasks.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(group.tasks) { task in
                row(task)
            }
        }
    }

    private func row(_ task: Task) -> some View {
        let blocked = task.lane == "main" && model.mainSlotsRemaining == 0
        return Button {
            if model.addExistingToToday(task) {
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(task.lane == "temporary" ? "临时" : (blocked ? "主线已满" : "主线"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .opacity(blocked ? 0.4 : 1)
        .help(blocked ? "主线任务最多 4 个" : "加入今天")
        .accessibilityIdentifier("add-task-existing-row")
    }

    // MARK: - 新建

    private var createPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("任务名称")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            TextField("接下来，想完成什么？", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.card)
                )
                .accessibilityIdentifier("add-task-title-field")

            Text("所属项目")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)
            Picker("所属项目", selection: $newProjectID) {
                Text("无项目").tag("")
                ForEach(model.projects) { project in
                    Text(project.name).tag(project.id)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("add-task-project-picker")

            Spacer()
        }
    }
}

struct AddTaskPickerGroup: Identifiable {
    let id: String
    let title: String
    let color: String?
    let tasks: [Task]
}
