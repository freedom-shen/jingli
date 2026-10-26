import SwiftUI
import JingliCore

struct ProjectListView: View {
    @ObservedObject var model: AppModel

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 220), spacing: 14),
        count: 3
    )

    private var active: [Project] { model.activeProjects }
    private var finished: [Project] { model.finishedProjects }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !model.projects.isEmpty {
                    sectionHeader(
                        "进行中",
                        count: active.count,
                        hint: "新建的排前面"
                    )
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(active) { project in
                        projectCard(project)
                    }
                    temporaryTasksCard
                    newProjectCard
                }

                if !finished.isEmpty {
                    sectionHeader(
                        "已完结",
                        count: finished.count,
                        hint: "没有任务的项目自动沉到这里"
                    )
                    .padding(.top, 26)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(finished) { project in
                            finishedCard(project)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }

    private func sectionHeader(_ label: String, count: Int, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)

            Text("\(count) 个项目")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))

            Spacer()

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary.opacity(0.55))
        }
        .padding(.bottom, 14)
    }

    private func cardShell<Content: View>(
        height: CGFloat,
        opacity: Double = 1,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .opacity(opacity)
    }

    private func projectIcon(_ color: String, size: CGFloat = 38) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.projectColor(color).opacity(0.18))
                .frame(width: size, height: size)
            Image(systemName: "folder")
                .font(.system(size: size > 30 ? 15 : 13, weight: .medium))
                .foregroundStyle(Theme.projectColor(color))
        }
    }

    private func projectCard(_ project: Project) -> some View {
        Button {
            model.openProject(project.id)
        } label: {
            cardShell(height: 160) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        projectIcon(project.color)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        if !project.description.isEmpty {
                            Text(project.description)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    Text("\(model.projectTaskCount(project.id)) 个任务")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 已完结：没有任务的项目，降权排在最后。
    private func finishedCard(_ project: Project) -> some View {
        Button {
            model.openProject(project.id)
        } label: {
            cardShell(height: 118, opacity: 0.58) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        projectIcon("slate", size: 32)

                        Spacer()

                        HStack(spacing: 5) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                            Text("已完结")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }

                    Text(project.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Spacer(minLength: 0)

                    Text("0 个任务")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var temporaryTasksCard: some View {
        Button {
            model.openTemporaryTasks()
        } label: {
            cardShell(height: 160) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        projectIcon("slate")

                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                                .frame(width: 24, height: 24)
                            Image(systemName: "tray")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("临时任务")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Text("随手记的事放这里，不占主线名额")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)

                    Text("\(model.temporaryTaskCount) 件任务")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("temporary-tasks-card")
    }

    private var newProjectCard: some View {
        Button {
            model.openProjectEditor(nil)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                Text("新建项目")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-project-button")
    }
}
