import AppKit
import SwiftUI
import JingliCore

/// 设置页「手机网页」区块：开关、配对链接、重新生成。
struct RemoteWebSettingsContent: View {
    @ObservedObject var controller: RemoteWebController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "开启手机网页（远程加任务）",
                isOn: Binding(
                    get: { controller.isEnabled },
                    set: { controller.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .accessibilityIdentifier("remote-web-toggle")

            Text("用 Tailscale 把手机和这台 Mac 放进同一个虚拟局域网，手机浏览器打开下面的链接就能看今天、加临时任务、勾完成。Mac 要开机并联网；关掉开关立刻停止。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.isEnabled {
                if let error = controller.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tomato)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Text(controller.isRunning ? "运行中 · 端口 \(String(controller.port))" : "未运行")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(controller.isRunning ? Theme.projectColor("sage") : Theme.textSecondary)

                    Spacer()

                    Button("刷新地址") {
                        controller.refreshAddresses()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("remote-web-refresh")

                    Button("重新生成链接") {
                        controller.regenerateToken()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("remote-web-regenerate")
                }

                if controller.addresses.isEmpty {
                    Text("还没拿到可用地址：确认这台 Mac 已连 Wi‑Fi 或 Tailscale。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(controller.addresses) { address in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(address.label)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                Text(address.url)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .accessibilityIdentifier("remote-web-address-\(address.id)")
                            }
                            Spacer(minLength: 4)
                            Button("复制") {
                                copy(address.url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("remote-web-copy-\(address.id)")
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                    }
                }

                if !controller.hasTailscaleAddress {
                    Text("没有检测到 Tailscale 地址：先在 Mac 和 iPhone 都安装 Tailscale，用同一个账号登录（Mac 端保持开启）。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.projectColor("amber"))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("链接里的 token 等于密码：别转发给别人；怀疑泄露就点「重新生成链接」。手机 Safari 可以「添加到主屏幕」，用起来像个小 App。")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
