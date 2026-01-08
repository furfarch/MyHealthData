import Foundation
import CloudKit

/// Minimal CloudKit manager scaffold.
final class CloudKitManager {
    static let shared = CloudKitManager()

    // Default container name used in entitlements. Change if needed.
    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"
    var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    private init() {}

    var isCloudAvailable: Bool {
        // At repo level we assume entitlement will enable CloudKit; runtime checks happen when used.
        true
    }

    // Map a MedicalRecord's basic fields to CKRecord
    func mapToCKRecord(_ recordID: String, record: MedicalRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: recordID)
        let ckRecord = CKRecord(recordType: "MedicalRecord", recordID: id)
        ckRecord["uuid"] = record.uuid as NSString
        ckRecord["createdAt"] = record.createdAt as NSDate
        ckRecord["updatedAt"] = record.updatedAt as NSDate
        ckRecord["isPet"] = NSNumber(value: record.isPet)
        ckRecord["personalFamilyName"] = record.personalFamilyName as NSString
        ckRecord["personalGivenName"] = record.personalGivenName as NSString
        ckRecord["personalNickName"] = record.personalNickName as NSString
        ckRecord["personalName"] = record.personalName as NSString
        // ... add more fields as required for syncing
        return ckRecord
    }

    // Upload a record (basic save; returns recordName)
    func upload(record: MedicalRecord) async throws -> String {
        guard isCloudAvailable else { throw NSError(domain: "CloudKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cloud not available"]) }
        let idString = record.cloudRecordName ?? record.uuid
        let ckRecord = mapToCKRecord(idString, record: record)
        let db = container.privateCloudDatabase
        return try await withCheckedThrowingContinuation { cont in
            db.save(ckRecord) { saved, error in
                if let error = error { cont.resume(throwing: error); return }
                guard let saved = saved else { cont.resume(throwing: NSError(domain: "CloudKit", code: 3, userInfo: nil)); return }
                cont.resume(returning: saved.recordID.recordName)
            }
        }
    }

    // Create a CKShare for a specific CKRecord
    func createShare(for recordID: CKRecord.ID, completion: @escaping (CKShare?, Error?) -> Void) {
        let db = container.privateCloudDatabase
        db.fetch(withRecordID: recordID) { record, error in
            if let err = error { completion(nil, err); return }
            guard let record = record else { completion(nil, NSError(domain: "CloudKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Record not found"])) ; return }

            let share = CKShare(rootRecord: record)
            share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

            let modifyOp = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
            modifyOp.modifyRecordsCompletionBlock = { saved, deleted, opError in
                completion(share, opError)
            }
            db.add(modifyOp)
        }
    }
}
