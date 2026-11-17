import SwiftUI
import CloudKit

@main
struct JingliProbeApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var lines: [String] = ["启动中…"]

    var body: some View {
        NavigationStack {
            List {
                Section("设备") {
                    Text("\(UIDevice.current.name) · iOS \(UIDevice.current.systemVersion)")
                }
                Section("CloudKit") {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.footnote.monospaced())
                    }
                }
            }
            .navigationTitle("Jingli CloudKit 探针")
            .task { await run() }
        }
    }

    func log(_ s: String) {
        print("[probe] \(s)")
        lines.append(s)
    }

    func run() async {
        lines = []
        let container = CKContainer(identifier: "iCloud.com.freedom-shen.jingli")
        do {
            let status = try await container.accountStatus()
            log("accountStatus = \(status.rawValue)  (1=可用)")
            guard status == .available else { log("iCloud 账号不可用，停止"); return }

            let zoneID = CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName)
            let db = container.privateCloudDatabase
            _ = try? await db.save(CKRecordZone(zoneID: zoneID))
            log("zone 就绪: \(zoneID.zoneName)")

            let recordID = CKRecord.ID(recordName: "probe-\(UUID().uuidString.prefix(8))", zoneID: zoneID)
            let record = CKRecord(recordType: "Change", recordID: recordID)
            record["entity"] = "probe" as CKRecordValue
            record["valueJSON"] = "\"hello from iPhone\"" as CKRecordValue
            record["ms"] = Int64(Date().timeIntervalSince1970 * 1000)
            try await db.save(record)
            log("写入成功: \(recordID.recordName)")

            let back = try await db.record(for: recordID)
            log("读回成功: entity=\(back["entity"] as? String ?? "nil")")

            let query = CKQuery(recordType: "Change", predicate: NSPredicate(value: true))
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
            log("zone 内 Change 记录数: \(results.count)")
            log("完成 ✓")
        } catch {
            log("失败: \(error)")
            print("[probe] error = \(error)")
        }
    }
}
