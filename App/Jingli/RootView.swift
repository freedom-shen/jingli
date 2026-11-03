import SwiftUI
import Combine
import JingliCore

struct RootView: View {
    @ObservedObject private var model = AppServices.shared.model
    @ObservedObject private var floatingPanel = FloatingPanelController.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                navigationBar
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

    private var navigationBar: some View {
        HStack(spacing: 8) {
            navigationButton("今日任务", icon: "checklist", selected: model.page == .day, identifier: "today-navigation") {
                model.page = .day
            }
            navigationButton("项目", icon: "folder", selected: isProjectPage, identifier: "projects-button") {
                model.openProjects()
            }
            navigationButton("临时任务", icon: "bolt", selected: model.page == .temporaryTasks, identifier: "temporary-navigation") {
                model.openTemporaryTasks()
            }
            Spacer()
            navigationButton("统计", icon: "chart.bar", selected: model.page == .stats, identifier: "stats-button") {
                model.openStats()
            }
            Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 18).padding(.horizontal, 6)
            navigationButton("设置", icon: "gearshape", selected: model.page == .settings, identifier: "settings-button") {
                model.openSettings()
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(Theme.card.opacity(0.45))
        .overlay(alignment: .bottom) { Divider().overlay(Color.white.opacity(0.04)) }
    }

    private var isProjectPage: Bool {
        switch model.page {
        case .projects, .project: return true
        default: return false
        }
    }

    private func navigationButton(_ title: String, icon: String, selected: Bool, identifier: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 36, height: 34)
            .contentShape(Rectangle())
            .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
            .background(selected ? Theme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
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

                if model.dayStarted, model.todayEstimateTotal > 0 {
                    Text("预计 \(model.todayEstimateTotal) 个番茄")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 0.91, green: 0.70, blue: 0.64))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.tomato.opacity(0.12)))
                        .overlay(Capsule().stroke(Theme.tomato.opacity(0.28), lineWidth: 1))
                        .accessibilityLabel("今天预计 \(model.todayEstimateTotal) 个番茄")
                        .accessibilityIdentifier("today-estimate-total")
                }

                if model.dayStarted {
                    iconButton("arrow.counterclockwise", label: "重置今日计划", identifier: "reset-day-button") {
                        model.resetDay()
                    }
                }

                iconButton("plus", label: "添加任务", identifier: "new-task-button") {
                    model.openAddTask()
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

            iconButton("pip", label: floatingPanel.isVisible ? "隐藏浮窗" : "显示浮窗", identifier: "show-floating-panel") {
                floatingPanel.toggleVisibility()
            }
            .tint(floatingPanel.isVisible ? Theme.accent : Theme.textSecondary)
            .accessibilityValue(floatingPanel.isVisible ? "已显示" : "已隐藏")
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 18)
    }

    private var timerControls: some View {
        HStack(spacing: 8) {
            Text(model.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(model.isOnBreak ? Theme.breakGreen : Theme.accent)
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
        .help(label)
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
