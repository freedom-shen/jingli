import Darwin
import Foundation
import JingliCore
import OSLog

/// 手机网页（远程加任务）的生命周期与配对信息。
///
/// - 开关、端口、token 都存在本地 `setting` 表（设备本地，不参与同步）。
/// - 关掉开关 = 立刻停止监听；重新生成 token = 旧链接全部失效。
/// - 地址列表从本机网卡读：Tailscale 的 100.x 排前面，其次是局域网。
@MainActor
final class RemoteWebController: ObservableObject {
    struct Address: Identifiable, Equatable {
        let id: String
        let label: String
        let url: String
    }

    static let enabledKey = "remote_web_enabled"
    static let portKey = "remote_web_port"
    static let tokenKey = "remote_web_token"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = RemoteWebServer.defaultPort
    @Published private(set) var addresses: [Address] = []
    @Published private(set) var errorMessage: String?

    /// 网页改了数据后通知 App 刷新（由 AppDelegate 在主线程设置）。
    let changeRelay = RemoteWebChangeRelay()

    private let store: WorkspaceStore
    private var server: RemoteWebServer?
    private var token: String
    private let log = Logger(subsystem: "com.freedom-shen.jingli", category: "remote-web")

    init(store: WorkspaceStore) {
        self.store = store
        self.isEnabled = (try? store.settingValue(Self.enabledKey)) == "1"
        self.token = (try? store.settingValue(Self.tokenKey)) ?? ""
        if token.isEmpty {
            token = Self.makeToken()
            try? store.setSettingValue(Self.tokenKey, token)
        }
        let storedPort = (try? store.settingValue(Self.portKey)).flatMap(UInt16.init)
        self.port = storedPort ?? RemoteWebServer.defaultPort
    }

    // MARK: - Lifecycle

    func startIfEnabled() {
        guard isEnabled, server == nil else { return }
        start()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        try? store.setSettingValue(Self.enabledKey, enabled ? "1" : "0")
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func regenerateToken() {
        token = Self.makeToken()
        try? store.setSettingValue(Self.tokenKey, token)
        if isRunning {
            stop()
            start()
        } else {
            refreshAddresses()
        }
    }

    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        addresses = []
        errorMessage = nil
    }

    private func start() {
        guard server == nil else { return }
        errorMessage = nil

        let relay = changeRelay
        var webServer = RemoteWebServer(
            database: store.database,
            token: token,
            port: port,
            onChange: { relay.fire() }
        )
        do {
            try webServer.start()
        } catch {
            // 端口被占用时退到系统分配的端口，配对链接会跟着变，但仍可用。
            guard case RemoteWebServer.WebError.bindFailed(EADDRINUSE) = error else {
                errorMessage = error.localizedDescription
                log.error("remote web start failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            let fallback = RemoteWebServer(
                database: store.database,
                token: token,
                port: 0,
                onChange: { relay.fire() }
            )
            do {
                try fallback.start()
                webServer = fallback
            } catch {
                errorMessage = error.localizedDescription
                log.error("remote web fallback failed: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        finishStart(webServer)
    }

    func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        changeRelay.set(handler)
    }

    private func finishStart(_ server: RemoteWebServer) {
        self.server = server
        self.port = server.port
        self.isRunning = true
        try? store.setSettingValue(Self.portKey, String(server.port))
        refreshAddresses()
        log.info("remote web listening on port \(server.port, privacy: .public)")
    }

    // MARK: - Pairing info

    func refreshAddresses() {
        guard isRunning else {
            addresses = []
            return
        }
        let interfaces = Self.ipv4Interfaces()
        var result: [Address] = []

        for interface in interfaces {
            let kind: (String, String)?
            if Self.isTailscale(interface) {
                kind = ("Tailscale", "tailscale")
            } else if Self.isPrivateLAN(interface.address) {
                kind = ("局域网 \(interface.name)", "lan-\(interface.name)")
            } else {
                kind = nil
            }
            guard let kind else { continue }
            result.append(
                Address(
                    id: "\(kind.1)-\(interface.address)",
                    label: kind.0,
                    url: "http://\(interface.address):\(port)/?t=\(token)"
                )
            )
        }

        // Tailscale 优先（家里 Wi‑Fi 和公司网络都能用），同标签内按地址排序。
        result.sort { lhs, rhs in
            let lhsRank = lhs.label == "Tailscale" ? 0 : 1
            let rhsRank = rhs.label == "Tailscale" ? 0 : 1
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.url < rhs.url
        }
        addresses = result
    }

    var primaryURL: String? {
        addresses.first?.url
    }

    var hasTailscaleAddress: Bool {
        addresses.contains { $0.label == "Tailscale" }
    }

    // MARK: - Helpers

    private static func makeToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private struct Interface {
        let name: String
        let address: String
    }

    private static func ipv4Interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result: [Interface] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            defer { pointer = interface.ifa_next }
            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }

            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let resultCode = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard resultCode == 0 else { continue }
            let text = String(cString: host)
            guard !text.isEmpty, text != "0.0.0.0" else { continue }
            result.append(Interface(name: String(cString: interface.ifa_name), address: text))
        }
        return result
    }

    private static func isTailscale(_ interface: Interface) -> Bool {
        guard interface.address.hasPrefix("100.") else { return false }
        let parts = interface.address.split(separator: ".")
        guard parts.count == 4, let second = Int(parts[1]) else { return false }
        return (64...127).contains(second)
    }

    private static func isPrivateLAN(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 192, parts[1] == 168 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 172, (16...31).contains(parts[1]) { return true }
        return false
    }
}


/// 线程安全的一次性回调转发：HTTP 服务线程触发，App 在主线程接收。
final class RemoteWebChangeRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    func set(_ handler: (@Sendable () -> Void)?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func fire() {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?()
    }
}
