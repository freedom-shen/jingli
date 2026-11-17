import SwiftUI
import JingliCore

/// 任务详情：改标题 / 备注 / 预估，完成后可删除（删除要二次确认，和 CLI 的 --confirm 对齐）。
struct TaskDetailView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let taskID: String

    @State private var title = ""
    @State private var note = ""
    @State private var estimate: Int?
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var errorText: String?

    private var task: JingliCore.Task? {
        model.snapshot?.todayTasks.first { $0.id == taskID }
            ?? model.projectGroups.flatMap(\.tasks).first { $0.id == taskID }
    }

    private var projectName: String? {
        guard let id = task?.projectID else { return nil }
        return model.projects[id]?.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let task {
                        metaLine(task)
                        titleField
                        infoCard(task)
                        noteCard
                        deleteButton
                        if let errorText {
                            Text(errorText).font(.system(size: 11.5)).foregroundStyle(Tokens.tomato)
                        }
                    } else {
                        Text("任务不存在").foregroundStyle(Tokens.text3).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(Tokens.bg)
            .navigationTitle("任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.foregroundStyle(Tokens.text3)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("taskdetail.save")
                        .foregroundStyle(Tokens.accent)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
            // 用 alert 而不是 confirmationDialog：后者在手机上只渲染破坏性按钮，
            // 看不到「取消」，用户只能靠点外面退出，不明确。
            .alert("删除这条任务？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { delete() }
            } message: {
                Text("删除后不可撤销，它在今日记录里的分摊也会一起消失。")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metaLine(_ task: JingliCore.Task) -> some View {
        HStack(spacing: 8) {
            Text(task.lane == "main" ? "主线" : "临时")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Tokens.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
            if let projectName {
                Text(projectName).font(.system(size: 11)).foregroundStyle(Tokens.text3)
            }
            Spacer()
            if task.done {
                Text("已完成").font(.system(size: 11)).foregroundStyle(Tokens.green)
            }
        }
        .padding(.horizontal, 4)
    }

    private var titleField: some View {
        TextField("", text: $title, axis: .vertical)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Tokens.text)
            .lineLimit(1...3)
            .padding(14)
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private func infoCard(_ task: JingliCore.Task) -> some View {
        VStack(spacing: 0) {
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
                    if let estimate {
                        Text("\(estimate)").font(.system(size: 15, weight: .medium))
                            .monospacedDigit().foregroundStyle(Tokens.text).frame(minWidth: 22)
                    } else {
                        Text("未估").font(.system(size: 11.5))
                            .foregroundStyle(Tokens.text3).frame(minWidth: 22)
                    }
                    Button { adjust(1) } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tokens.text2)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("个番茄").font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
                }
            }
            .padding(.vertical, 12)

            Divider().overlay(Tokens.line)

            HStack {
                Text("今天已用").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                Spacer()
                Text(creditText)
                    .font(.system(size: 13)).foregroundStyle(Tokens.text2)
            }
            .padding(.vertical, 12)

            Divider().overlay(Tokens.line)

            HStack {
                Text("创建时间").font(.system(size: 13)).foregroundStyle(Tokens.text3)
                Spacer()
                Text(Self.displayDate(task.createdAt))
                    .font(.system(size: 12)).foregroundStyle(Tokens.text3)
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
                .lineLimit(4...8)
        }
        .padding(14)
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
    }

    private var deleteButton: some View {
        Button {
            confirmDelete = true
        } label: {
            Text("删除任务")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tokens.tomato)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(Tokens.tomato.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(Tokens.tomato.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private static let iso = ISO8601DateFormatter()
    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static func displayDate(_ raw: String) -> String {
        guard let date = iso.date(from: raw) else { return String(raw.prefix(16)) }
        return local.string(from: date)
    }

    private var creditText: String {
        let credit = model.credits[taskID] ?? 0
        return credit == credit.rounded() ? "\(Int(credit)) 个番茄" : String(format: "%.1f 个番茄", credit)
    }

    private func adjust(_ delta: Int) {
        let next = max(0, min(32, (estimate ?? 0) + delta))
        estimate = next == 0 ? nil : next
    }

    private func loadIfNeeded() {
        guard !loaded, let task else { return }
        title = task.title
        note = task.note
        estimate = task.estimate
        loaded = true
    }

    private func save() {
        do {
            _ = try model.updateTask(id: taskID, title: title, note: note, estimate: estimate)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try model.deleteTask(id: taskID)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
