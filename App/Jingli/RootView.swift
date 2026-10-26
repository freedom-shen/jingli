import SwiftUI
import Combine
import JingliCore

struct RootView: View {
    @ObservedObject private var model = AppServices.shared.model

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                content
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.isTaskEditorPresented) {
            TaskEditorView(
                model: model,
                defaultProjectID: model.taskEditorProjectID,
                fixedLane: model.taskEditorLane
            )
        }
        .sheet(isPresented: $model.isAddTaskPresented) {
            AddTaskView(model: model)
        }
        .sheet(isPresented: $model.isProjectEditorPresented) {
            ProjectEditorView(model: model, project: model.editingProject)
        }
        .sheet(item: $model.detailTask) { task in
            TaskDetailView(
                model: model,
                task: task,
                locked: model.page == .day && task.lane == "main"
            )
        }
        .sheet(isPresented: $model.isCommandBarPresented) {
            CommandBarView(model: model)
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { model.reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.page {
        case .projects:
            ProjectListView(model: model)
        case .project:
            ProjectDetailView(model: model)
        case .temporaryTasks:
            TemporaryTasksView(model: model)
        case .stats:
            StatsView(model: model)
        case .settings:
            SettingsView(model: model)
        case .day:
            if let snapshot = model.snapshot {
                if snapshot.dayStarted {
                    TodayView(model: model, snapshot: snapshot)
                } else {
                    DayStartView(model: model, snapshot: snapshot)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if model.page != .day {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("back-button")
            }

            Text(pageTitle)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

            if model.isBusy {
                timerControls
            }

            switch model.page {
            case .day:
                Text(countText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                if model.dayStarted {
                    Button("重置") {
                        model.resetDay()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("reset-day-button")
                }

                iconButton("chart.bar", label: "统计", identifier: "stats-button") {
                    model.openStats()
                }

                iconButton("gearshape", label: "设置", identifier: "settings-button") {
                    model.openSettings()
                }

                iconButton("plus", label: "添加今日任务", identifier: "new-task-button") {
                    model.openAddTask()
                }

                iconButton("folder", label: "项目", identifier: "projects-button") {
                    model.openProjects()
                }
            case .projects:
                iconButton("plus", label: "新建项目", identifier: "new-project-button") {
                    model.openProjectEditor(nil)
                }
            case .project:
                iconButton("plus", label: "新建任务", identifier: "new-project-task-button") {
                    model.openTaskEditor(projectID: model.currentProject()?.id)
                }
                iconButton("pencil", label: "编辑项目", identifier: "edit-project-button") {
                    model.openProjectEditor(model.currentProject())
                }
            case .temporaryTasks:
                iconButton("plus", label: "新建临时任务", identifier: "new-temporary-task-button") {
                    model.openTaskEditor(lane: "temporary")
                }
            case .stats, .settings:
                EmptyView()
            }

            Button("浮窗") {
                FloatingPanelController.shared.show()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("show-floating-panel")
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var timerControls: some View {
        HStack(spacing: 8) {
            Text(model.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .monospacedDigit()

            if model.isOnBreak {
                Button("跳过休息") {
                    model.skipBreak()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(model.timerIsPaused ? "继续" : "暂停") {
                    if model.timerIsPaused {
                        model.resumeFocus()
                    } else {
                        model.pauseFocus()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("废弃") {
                    model.abandonFocus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func iconButton(
        _ systemName: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var pageTitle: String {
        switch model.page {
        case .projects:
            return "项目"
        case .project:
            return model.currentProject()?.name ?? "项目"
        case .temporaryTasks:
            return "临时任务"
        case .stats:
            return "统计"
        case .settings:
            return "设置"
        case .day:
            return model.dayStarted ? "今日任务" : "开启一天"
        }
    }

    private var countText: String {
        if model.dayStarted {
            let mainCount = model.snapshot?.todayTasks.filter { $0.lane == "main" }.count ?? 0
            return "主线 \(mainCount) / 4"
        }
        return "主线已选 \(model.selectedMainCount) / 4"
    }
}
