import SwiftUI
import JingliCore

/// 设置：现阶段只显示「数据在哪、有多少、同步还没接」。
/// 等 M3 的 transport 接上，这里再加同步状态和手动同步。
struct SettingsView: View {
    @Environment(IOSAppModel.self) private var model
    @State private var syncing = false
    @State private var showModelConfig = false

    private var fileSize: String {
        let url = AppPaths.databaseURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attributes[.size] as? Int else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var taskCount: Int {
        (try? model.store.taskCount()) ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                section("数据", rows: [
                    ("externaldrive", "数据库", fileSize),
                    ("number", "任务总数", "\(taskCount)"),
                    ("lock.shield", "位置", "App Group"),
                ])
                syncSection
                hint.padding(.top, 16)
                modelSection
                section("关于", rows: [
                    ("app.badge", "版本", version),
                    ("iphone", "平台", "iOS"),
                ])
                Text("数据只在你的设备和 iCloud 私有库里；不经过任何第三方服务。")
                    .font(.system(size: 10.5)).foregroundStyle(Tokens.text3)
                    .padding(.top, 14).padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .task { await model.refreshSyncStatus() }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("助手")
                .font(.system(size: 10.5)).tracking(1.2)
                .foregroundStyle(Tokens.text3)
                .padding(.leading, 4).padding(.bottom, 8).padding(.top, 18)

            VStack(spacing: 0) {
                row("sparkles", "模型", model.assistantReady ? model.llmConfig.model : "未配置")
                Divider().overlay(Tokens.line).padding(.leading, 46)
                Button {
                    showModelConfig = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "key")
                            .font(.system(size: 12)).foregroundStyle(Tokens.accent).frame(width: 22)
                        Text(model.assistantReady ? "修改配置" : "填 API Key")
                            .font(.system(size: 13.5)).foregroundStyle(Tokens.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.modelConfig")
            }
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
        }
        .sheet(isPresented: $showModelConfig) { ModelConfigSheet() }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("同步")
                .font(.system(size: 10.5)).tracking(1.2)
                .foregroundStyle(Tokens.text3)
                .padding(.leading, 4).padding(.bottom, 8).padding(.top, 18)

            VStack(spacing: 0) {
                row("icloud", "iCloud", "已开启")
                Divider().overlay(Tokens.line).padding(.leading, 46)
                row("arrow.triangle.2.circlepath", "待同步", "\(model.syncStatus?.pending ?? 0) 条")
                Divider().overlay(Tokens.line).padding(.leading, 46)
                row("clock", "上次同步", lastSyncText)
                if let error = model.syncStatus?.lastError {
                    Divider().overlay(Tokens.line).padding(.leading, 46)
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(Tokens.tomato).frame(width: 22)
                        Text(error).font(.system(size: 11)).foregroundStyle(Tokens.tomato)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }

                Divider().overlay(Tokens.line).padding(.leading, 46)
                Button {
                    _Concurrency.Task {
                        syncing = true
                        await model.syncNow()
                        syncing = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12)).foregroundStyle(Tokens.accent).frame(width: 22)
                        Text(syncing ? "同步中…" : "立即同步")
                            .font(.system(size: 13.5)).foregroundStyle(Tokens.accent)
                        Spacer()
                        if syncing { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.syncNow")
                .disabled(syncing)
            }
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12)).foregroundStyle(Tokens.text3).frame(width: 22)
            Text(title).font(.system(size: 13.5)).foregroundStyle(Tokens.text)
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(Tokens.text3)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    private var lastSyncText: String {
        guard let date = model.syncStatus?.lastSyncAt else { return "还没同步" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("设置").font(.system(size: 30, weight: .bold)).foregroundStyle(Tokens.text)
            Text("数据与同步").font(.system(size: 11.5)).foregroundStyle(Tokens.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func section(_ title: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10.5)).tracking(1.2)
                .foregroundStyle(Tokens.text3)
                .padding(.leading, 4).padding(.bottom, 8).padding(.top, 18)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 10) {
                        Image(systemName: row.0)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.text3)
                            .frame(width: 22)
                        Text(row.1).font(.system(size: 13.5)).foregroundStyle(Tokens.text)
                        Spacer()
                        Text(row.2).font(.system(size: 12)).foregroundStyle(Tokens.text3)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)

                    if index < rows.count - 1 {
                        Divider().overlay(Tokens.line).padding(.leading, 46)
                    }
                }
            }
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.line))
        }
    }

    private var hint: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12)).foregroundStyle(Tokens.accent)
            Text("数据只在你自己的 iCloud 私有库里，主 App 和 Widget 共用同一份。")
                .font(.system(size: 11)).foregroundStyle(Tokens.text3)
            Spacer()
        }
        .padding(12)
        .background(Tokens.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tokens.accent.opacity(0.16)))
        .padding(.top, 4)
    }
}
