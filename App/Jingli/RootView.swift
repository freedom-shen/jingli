import SwiftUI
import JingliCore

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar

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
        .frame(minWidth: 1100, minHeight: 700)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.isTaskEditorPresented) {
            TaskEditorView(model: model)
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

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(model.dayStarted ? "今日任务" : "开启一天")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Spacer()

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

            Button {
                model.openTaskEditor()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("new-task-button")

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

    private var countText: String {
        if model.dayStarted {
            let mainCount = model.snapshot?.todayTasks.filter { $0.lane == "main" }.count ?? 0
            return "主线 \(mainCount) / 4"
        }
        return "主线已选 \(model.selectedMainCount) / 4"
    }
}
