import CloudKit
import XCTest
@testable import JingliCore
@testable import JingliSync

/// 只测映射，不联网：CKRecord 的创建和读取在本地就能完成。
final class CloudKitMappingTests: XCTestCase {
    private let zoneID = CKRecordZone.ID(zoneName: "JingliZone", ownerName: CKCurrentUserDefaultName)

    func testChangeSurvivesRecordRoundTrip() {
        let change = SyncChange(
            seq: 42,
            entity: "task",
            entityID: "task-1",
            field: "title",
            valueJSON: #""评审设计稿""#,
            rev: "0000018a2f3b4c5d-ABC123-00000000002a",
            deviceID: "ABC123",
            ms: 1_763_373_600_000
        )

        let record = CloudKitTransport.record(for: change, zoneID: zoneID)
        XCTAssertEqual(record.recordID.recordName, "ABC123:42", "recordName 必须是 deviceID:seq")
        XCTAssertEqual(record.recordType, "SyncChange")

        let decoded = CloudKitTransport.change(from: record)
        XCTAssertEqual(decoded, change)
        XCTAssertEqual(decoded?.changeID, change.changeID)
    }

    func testIncompleteRecordIsDropped() {
        let record = CKRecord(
            recordType: "SyncChange",
            recordID: CKRecord.ID(recordName: "ABC123:1", zoneID: zoneID)
        )
        record["entity"] = "task" as CKRecordValue
        XCTAssertNil(CloudKitTransport.change(from: record), "缺字段应丢弃而不是崩")
    }
}
