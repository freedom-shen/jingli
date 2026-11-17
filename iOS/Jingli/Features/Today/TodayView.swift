import SwiftUI
import JingliCore

struct TodayView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var showAdd = false
    @State private var detailTask: JingliCore.Task?
    @State private var showAssistant = false

    private var mainTasks: [JingliCore.Task] {
        (model.snapshot?.todayTasks.filter { $0.lane == "main" } ?? [])
            .sorted { lhs, rhs in
                if lhs.done != rhs.done { return !lhs.done }
                return lhs.sortOrder < rhs.sortOrder
            }
    }
    private var tempTasks: [JingliCore.Task] {
        model.snapshot?.todayTasks.filter { $0.lane == "temporary" } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if model.isOnBreak {
                    BreakBanner().padding(.bottom, 12)
                }
                header
                if let stats = model.stats {
                    SummaryStrip(stats: stats, mainCount: mainTasks.count)
                        .padding(.top, 14)
                }

                if mainTasks.isEmpty && tempTasks.isEmpty {
                    emptyToday.padding(.top, 26)
                }

                sectionTitle("主线任务", trailing: "\(mainTasks.count) / 4")
                ForEach(mainTasks) { task in
                    MainTaskCard(task: task, project: projectName(for: task))
                        .contentShape(Rectangle())
                        .onTapGesture { detailTask = task }
                        .padding(.bottom, 10)
                }

                if !tempTasks.isEmpty {
                    sectionTitle("临时任务", trailing: "\(tempTasks.count) 件")
                        .padding(.top, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(tempTasks.enumerated()), id: \.element.id) { index, task in
                            TempRow(task: task, credit: credit(for: task))
                            if index < tempTasks.count - 1 {
                                Divider().overlay(Tokens.line).padding(.leading, 14)
                            }
                        }
                    }
                    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
                }

                if let error = model.errorText {
                    Text(error).font(.footnote).foregroundStyle(.orange).padding(.top, 16)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
        .sheet(isPresented: $showAdd) { AddTaskView() }
        .sheet(item: $detailTask) { task in TaskDetailView(taskID: task.id) }
        .sheet(isPresented: $showAssistant) { AssistantView() }
        .task {
            if CommandLine.arguments.contains("-addsheet") { showAdd = true }
            if CommandLine.arguments.contains(where: { $0.hasPrefix("-ask=") }) { showAssistant = true }
            if CommandLine.arguments.contains("-detail") {
                detailTask = mainTasks.first { !$0.done } ?? mainTasks.first
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.today).font(.footnote).foregroundStyle(Tokens.text3)
                Text("今天").font(.system(size: 30, weight: .bold)).foregroundStyle(Tokens.text)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { showAdd = true } label: { iconButton("plus") }
                    .buttonStyle(.plain)
                Button { showAssistant = true } label: { iconButton("sparkles", tint: Tokens.accent) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func iconButton(_ name: String, tint: Color = Tokens.text2) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(name == "mic.fill" ? 0.16 : 0.06), in: Circle())
    }

    /// 今天一件都没有时的引导：不是错误，是还没安排。
    private var emptyToday: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("今天还没有任务").font(.system(size: 16, weight: .semibold)).foregroundStyle(Tokens.text)
                Text("从项目里挑几件，或者直接跟助手说一句话。").font(.system(size: 12)).foregroundStyle(Tokens.text3)
            }
            HStack(spacing: 9) {
                Button {
                    showAdd = true
                } label: {
                    Text("新建任务")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Tokens.text)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(Tokens.line))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.empty.newTask")

                Button {
                    showAssistant = true
                } label: {
                    Text("跟助手说")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Tokens.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today.empty.assistant")
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
            Spacer()
            Text(trailing).font(.system(size: 11)).foregroundStyle(Tokens.text3)
        }
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private func projectName(for task: JingliCore.Task) -> String? {
        guard let id = task.projectID else { return nil }
        return model.projects[id]?.name
    }

    private func credit(for task: JingliCore.Task) -> Double {
        model.credits[task.id] ?? 0
    }
}

// MARK: - 组件

private struct SummaryStrip: View {
    let stats: TodayStats
    let mainCount: Int

    private var toLongBreak: String {
        let remaining = FocusStreak.threshold - stats.pomodoros % FocusStreak.threshold
        return stats.pomodoros > 0 && remaining == FocusStreak.threshold
            ? "该长休了"
            : "再 \(remaining) 个长休"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stats.pomodoros) 个番茄 · \(stats.focusSeconds / 60) 分钟")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Tokens.text)
                Text("已完成 \(stats.completedTasks) 件 · 主线 \(mainCount) 件")
                    .font(.system(size: 11)).foregroundStyle(Tokens.text3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(i < stats.pomodoros ? Tokens.tomato : Color.white.opacity(0.14))
                            .frame(width: 5, height: 5)
                    }
                }
                // 光有圆点会被误读成「更多」菜单，补一句说明它的含义
                Text(toLongBreak)
                    .font(.system(size: 9))
                    .foregroundStyle(Tokens.text3)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Tokens.tomato.opacity(0.16), Tokens.tomato.opacity(0.04)],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.tomato.opacity(0.22)))
    }
}

private struct MainTaskCard: View {
    @Environment(IOSAppModel.self) private var model
    let task: JingliCore.Task
    let project: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(task.done ? Tokens.text3 : Tokens.text)
                    .strikethrough(task.done, color: Tokens.text3)
                Spacer(minLength: 8)
                if !task.done {
                    Button {
                        model.startFocus(taskID: task.id)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Tokens.accent)
                            .frame(width: 30, height: 30)
                            .background(Tokens.accent.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                if let project {
                    HStack(spacing: 5) {
                        Circle().fill(Tokens.accent).frame(width: 5, height: 5)
                        Text(project).font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(Tokens.tomato).frame(width: 6, height: 6)
                    Text(creditText).font(.system(size: 11)).foregroundStyle(Tokens.text3)
                }
                Spacer()
                Button {
                    model.toggle(task)
                } label: {
                    Image(systemName: task.done ? "checkmark" : "")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        .frame(width: 24, height: 24)
                        .background(
                            task.done ? Tokens.accent : Color.clear, in: Circle()
                        )
                        .overlay(Circle().stroke(Color.white.opacity(task.done ? 0 : 0.22)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 11)
        }
        .padding(14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.line))
        .opacity(task.done ? 0.55 : 1)
    }

    private var creditText: String {
        let credit = model.credits[task.id] ?? 0
        let value = credit == credit.rounded() ? String(Int(credit)) : String(format: "%.1f", credit)
        if let estimate = task.estimate { return "\(value) · 预计 \(estimate)" }
        return value
    }
}

private struct TempRow: View {
    @Environment(IOSAppModel.self) private var model
    let task: JingliCore.Task
    let credit: Double

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.toggle(task)
            } label: {
                Circle()
                    .stroke(Color.white.opacity(task.done ? 0 : 0.22), lineWidth: 1.5)
                    .background(Circle().fill(task.done ? Tokens.accent : .clear))
                    .frame(width: 20, height: 20)
                    .overlay {
                        if task.done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.08))
                        }
                    }
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(task.done ? Tokens.text3 : Tokens.text)
                .strikethrough(task.done, color: Tokens.text3)
                .lineLimit(1)

            Spacer(minLength: 8)
            Text(credit == credit.rounded() ? String(Int(credit)) : String(format: "%.1f", credit))
                .font(.system(size: 11)).foregroundStyle(Tokens.text3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
