import Cocoa
import CloudKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

NSLog("[MAC] start")
let container = CKContainer(identifier: "iCloud.com.freedom-shen.jingli")
Task {
    do {
        let status = try await container.accountStatus()
        NSLog("[MAC] accountStatus=\(status.rawValue)")
    } catch { NSLog("[MAC] accountStatus failed: \(error)") }
    do {
        let id = try await container.userRecordID()
        NSLog("[MAC] userRecordID=\(id.recordName.prefix(6))")
    } catch { NSLog("[MAC] userRecordID failed: \(error)") }
    do {
        let zone = CKRecordZone(zoneID: CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName))
        _ = try await container.privateCloudDatabase.save(zone)
        NSLog("[MAC] zone ok")
    } catch { NSLog("[MAC] zone failed: \(error)") }
    do {
        let result = try await container.privateCloudDatabase.recordZoneChanges(
            inZoneWith: CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName),
            since: nil
        )
        NSLog("[MAC] pulled \(result.modificationResultsByID.count)")
    } catch { NSLog("[MAC] pull failed: \(error)") }
    exit(0)
}
app.run()
