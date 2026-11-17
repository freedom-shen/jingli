import SwiftUI
import JingliCore

struct ProjectsView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var showAdd = false

    private let columns = [
        GridItem(.flexible(), spacing: 11),
        GridItem(.flexible(), spacing: 11),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if model.projectGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("还没有项目").font(.system(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                            Text("先建一个项目，主线任务才有地方放。临时任务不需要项目。")
                                .font(.system(size: 12)).foregroundStyle(Tokens.text3)
                            Button {
                                showAdd = true
                            } label: {
                                Text("新建项目")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                                    .padding(.horizontal, 16).padding(.vertical, 9)
                                    .background(Tokens.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("projects.empty.new")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
                        .padding(.top, 18)
                    }

                    LazyVGrid(columns: columns, spacing: 11) {
                        ForEach(model.projectGroups) { group in
                            NavigationLink(value: group.id) {
                                ProjectCard(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationDestination(for: String.self) { id in
                ProjectDetailView(groupID: id)
            }
            .sheet(isPresented: $showAdd) { AddProjectView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("项目").font(.system(size: 30, weight: .bold)).foregroundStyle(Tokens.text)
                Text("\(model.projectGroups.count) 个分组 · \(openTasks) 件未完成")
                    .font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
            }
            Spacer()
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.text2)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("projects.add")
        }
        .padding(.top, 8)
    }

    private var openTasks: Int {
        model.projectGroups.reduce(0) { $0 + $1.openCount }
    }
}

private struct ProjectCard: View {
    let group: IOSAppModel.ProjectGroup

    private var tint: Color { Tokens.projectColor(group.project?.color ?? "slate") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(group.name)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Tokens.text3)
                    .lineLimit(1)
            }
            if let first = group.tasks.first(where: { !$0.done }) {
                Text(first.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 9)
            } else {
                Text("还没有任务")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.text3)
                    .padding(.top, 9)
            }
            Spacer(minLength: 10)
            HStack {
                Text("\(group.openCount) 件未完成")
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
                Spacer()
                Text("\(group.tasks.count) 件")
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
            }
        }
        .padding(14)
        .frame(minHeight: 112, alignment: .topLeading)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
    }
}

struct ProjectDetailView: View {
    @Environment(IOSAppModel.self) private var model
    let groupID: String
    @State private var detailTask: JingliCore.Task?
    @State private var showAddTask = false
    @State private var confirmDeleteProject = false
    @Environment(\.dismiss) private var dismissDetail

    private var group: IOSAppModel.ProjectGroup? {
        model.projectGroups.first { $0.id == groupID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let group {
                    header(group)
                    taskList(group)
                    Button {
                        showAddTask = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            Text("在这个项目里新建任务").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Tokens.accent)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Tokens.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.accent.opacity(0.26)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("project.addTask")
                    .padding(.top, 12)
                    if group.project != nil {
                        Button {
                            confirmDeleteProject = true
                        } label: {
                            Text("删除项目")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(Tokens.tomato)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Tokens.tomato.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.tomato.opacity(0.26)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("project.delete")
                        .padding(.top, 18)
                    }

                    if model.snapshot?.dayStarted == true {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.system(size: 10))
                            Text("今天已开始：新建主线会被拒绝，临时任务请在今天页添加")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Tokens.text3)
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detailTask) { task in TaskDetailView(taskID: task.id) }
        .alert("删除这个项目？", isPresented: $confirmDeleteProject) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let id = group?.project?.id {
                    try? model.deleteProject(id: id)
                }
                dismissDetail()
            }
        } message: {
            Text("项目会被删除，里面的任务变成「未分类」并保留下来。")
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskView(presetProjectID: group?.project?.id, presetProjectName: group?.name)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(group?.name ?? "项目")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.text)
            }
        }
    }

    private func header(_ group: IOSAppModel.ProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Tokens.projectColor(group.project?.color ?? "slate"))
                    .frame(width: 7, height: 7)
                Text("项目 · \(group.tasks.count) 个任务")
                    .font(.system(size: 11)).foregroundStyle(Tokens.text3)
            }
            Text(group.name)
                .font(.system(size: 26, weight: .bold)).foregroundStyle(Tokens.text)
            if let desc = group.project?.description, !desc.isEmpty {
                Text(desc).font(.system(size: 12)).foregroundStyle(Tokens.text3)
            }
        }
        .padding(.top, 6)
    }

    private func taskList(_ group: IOSAppModel.ProjectGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: 12) {
                    Button {
                        model.toggle(task)
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(task.done ? 0 : 0.22), lineWidth: 1.5)
                                .background(Circle().fill(task.done ? Tokens.accent : .clear))
                                .frame(width: 20, height: 20)
                            if task.done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(task.done ? Tokens.text3 : Tokens.text)
                            .strikethrough(task.done, color: Tokens.text3)
                        if let planned = task.plannedDate, !planned.isEmpty {
                            Text("已在今天 · \(planned)")
                                .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.text3)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                .onTapGesture { detailTask = task }

                if index < group.tasks.count - 1 {
                    Divider().overlay(Tokens.line)
                }
            }

            if group.tasks.isEmpty {
                Text("这个项目还没有任务").font(.system(size: 12))
                    .foregroundStyle(Tokens.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .padding(.horizontal, 14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
        .padding(.top, 18)
    }
}
