import AppKit
import SwiftUI
import UniformTypeIdentifiers
import JingliCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var missingShortcuts: [String] = []
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage("jingli.autoDND") private var autoDND = true
    @State private var backupMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("专注与勿扰") {
                    HStack {
                        Text("快捷指令联动")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(missingShortcuts.isEmpty ? "已配置" : "未配置")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                missingShortcuts.isEmpty ? Theme.projectColor("sage") : Theme.tomato
                            )
                    }

                    Toggle("开始番茄钟时自动进入勿扰", isOn: $autoDND)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)

                    Text("开始番茄钟时运行「Jingli Focus On」进入勿扰；完成、废弃、休息或退出时运行「Jingli Focus Off」。已有其他 Focus 时不会接管。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !missingShortcuts.isEmpty {
                        Text("缺少：\(missingShortcuts.joined(separator: "、"))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tomato)
                    }

                    HStack(spacing: 8) {
                        Button("重新检查") {
                            checkShortcuts()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("打开快捷指令") {
                            if let url = URL(string: "shortcuts://") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("计时固定 25 分钟；每轮后休息 5 分钟，连续完成 4 个钟长休 25 分钟；休息可跳过，不计入统计。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                section("通知") {
                    Text("轮次结束会发系统通知；勿扰开启时系统可能静音，完成弹窗仍会置顶显示。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("发送测试通知") {
                        CompletionNotifier.shared.requestAuthorization()
                        CompletionNotifier.shared.notify(
                            title: "精力管理",
                            body: "通知工作正常。"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                section("数据与备份") {
                    Text(AppPaths.supportDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)

                    if let latest = model.latestBackup() {
                        Text("最近备份：\(latest.date) · \(ByteCountFormatter.string(fromByteCount: Int64(latest.bytes), countStyle: .file))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("还没有备份。每天首次启动会自动备份，保留 14 天。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    HStack(spacing: 8) {
                        Button("立即备份") {
                            if let url = model.runBackupNow() {
                                backupMessage = "已备份到 \(url.lastPathComponent)"
                            } else {
                                errorMessage = "备份失败"
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("从备份导入…") {
                            importBackup()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("打开数据文件夹") {
                            NSWorkspace.shared.open(AppPaths.supportDirectory)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("导入只恢复项目与任务，不导入旧番茄记录。")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.8))
                }

                section("启动") {
                    Toggle("开机自动启动", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .onChange(of: launchAtLogin) { _, value in
                            do {
                                try LaunchAtLogin.set(value)
                            } catch {
                                launchAtLogin = LaunchAtLogin.isEnabled
                                errorMessage = "无法修改开机启动：\(error.localizedDescription)"
                            }
                        }
                    Text("默认关闭，只影响当前用户。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                section("关于") {
                    HStack {
                        Text("精力管理")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(versionText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("只管今天：跨天清空番茄记录，未完成任务回到未安排。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .padding(.top, 4)
        .accessibilityIdentifier("settings-page")
        .onAppear(perform: checkShortcuts)
        .alert(
            "提示",
            isPresented: Binding(
                get: { backupMessage != nil || errorMessage != nil },
                set: { if !$0 { backupMessage = nil; errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                backupMessage = nil
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? backupMessage ?? "")
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func checkShortcuts() {
        missingShortcuts = FocusController.shared.missingShortcuts()
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let summary = model.importBackup(from: url) {
            backupMessage = "已导入 \(summary.projects) 个项目、\(summary.tasks) 个任务"
        } else {
            errorMessage = "导入失败，请确认是精力管理导出的备份文件"
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "0.0.1")"
    }
}
