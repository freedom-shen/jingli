import CloudKit
import Foundation
import JingliCore
import JingliSync

/// Mac 端 CloudKit 自检：账号 → 建 zone → 推一条 → 拉回来。
/// 只在带 -ckcheck 启动参数时运行。
enum CloudKitCheck {
    static let containerID = "iCloud.com.freedom-shen.jingli"

    static func run() async {
        let container = CKContainer(identifier: containerID)
        do {
            let status = try await container.accountStatus()
            NSLog("[MACCK] accountStatus=\(status.rawValue) (1=available)")
        } catch {
            NSLog("[MACCK] accountStatus failed: \(error)")
        }

        let transport = CloudKitTransport(config: .init(containerIdentifier: containerID))
        let change = SyncChange(
            seq: 999_101,
            entity: "task",
            entityID: "macprobe-\(UUID().uuidString.prefix(8))",
            field: "title",
            valueJSON: #""mac probe""#,
            rev: "0000000000000001-MACPROBE-0000000000000001",
            deviceID: "MACPROBE",
            ms: Int64(Date().timeIntervalSince1970 * 1000)
        )

        do {
            let accepted = try await transport.push([change])
            NSLog("[MACCK] push accepted=\(accepted.count)")
            let (changes, cursor) = try await transport.pull(cursor: nil)
            let found = changes.contains { $0.changeID == change.changeID }
            NSLog("[MACCK] pull count=\(changes.count) foundOwn=\(found) hasCursor=\(cursor != nil)")
        } catch {
            NSLog("[MACCK] failed: \(error)")
        }
    }
}
