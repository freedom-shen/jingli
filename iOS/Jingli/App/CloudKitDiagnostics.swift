import CloudKit
import Foundation
import JingliCore
import JingliSync

/// 真机上的 CloudKit 自检：账号状态 → 写一条 → 拉回来。
/// 只在带 -ckcheck 启动参数时运行，正式路径不调用。
enum CloudKitDiagnostics {
    static let containerID = "iCloud.com.freedom-shen.jingli"

    static func run() async {
        let container = CKContainer(identifier: containerID)
        do {
            let status = try await container.accountStatus()
            NSLog("[CK] accountStatus=\(status.rawValue) (1=available)")
        } catch {
            NSLog("[CK] accountStatus failed: \(describe(error))")
        }

        do {
            let id = try await container.userRecordID()
            NSLog("[CK] userRecordID ok: \(id.recordName.prefix(6))…")
        } catch {
            NSLog("[CK] userRecordID failed: \(describe(error))")
        }

        do {
            let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName))
            _ = try await container.privateCloudDatabase.save(zone)
            NSLog("[CK] zone created")
        } catch {
            NSLog("[CK] zone save failed: \(describe(error))")
        }

        // 默认 zone 能不能写？用来区分「自定义 zone 被拒」还是「整个容器被拒」
        do {
            let record = CKRecord(recordType: "Probe", recordID: CKRecord.ID(recordName: "probe-default"))
            record["x"] = "1" as CKRecordValue
            _ = try await container.privateCloudDatabase.save(record)
            NSLog("[CK] default zone write ok")
        } catch {
            NSLog("[CK] default zone write failed: \(describe(error))")
        }

        let transport = CloudKitTransport(config: .init(containerIdentifier: containerID))
        let change = SyncChange(
            seq: 999_001,
            entity: "task",
            entityID: "probe-\(UUID().uuidString.prefix(8))",
            field: "title",
            valueJSON: #""probe""#,
            rev: "0000000000000001-PROBE-0000000000000001",
            deviceID: "PROBE",
            ms: Int64(Date().timeIntervalSince1970 * 1000)
        )

        do {
            let accepted = try await transport.push([change])
            NSLog("[CK] push accepted=\(accepted.count) ids=\(accepted)")
        } catch {
            NSLog("[CK] push failed: \(describe(error))")
            return
        }

        do {
            let (changes, cursor) = try await transport.pull(cursor: nil)
            let found = changes.contains { $0.changeID == change.changeID }
            NSLog("[CK] pull count=\(changes.count) foundOwn=\(found) hasCursor=\(cursor != nil)")
        } catch {
            NSLog("[CK] pull failed: \(describe(error))")
        }
    }
}


private func describe(_ error: Error) -> String {
    let ns = error as NSError
    var text = "\(ns.domain)#\(ns.code) \(ns.localizedDescription)"
    if let ck = error as? CKError {
        text += " ckCode=\(ck.code.rawValue)"
    }
    let info = ns.userInfo
    if let server = info["ServerErrorDescription"] as? String { text += " server=\(server)" }
    if let reasons = info["NSDebugDescription"] as? String { text += " debug=\(reasons)" }
    if let partial = info["CKPartialErrors"] as? [AnyHashable: Any], !partial.isEmpty {
        text += " partial=\(partial.values)"
    }
    return text
}
