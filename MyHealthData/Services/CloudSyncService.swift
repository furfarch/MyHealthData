import Foundation
import SwiftData
import CloudKit
import UIKit

/// Manual CloudKit sync layer for per-record opt-in syncing.
///
/// Why manual?
/// SwiftData's built-in CloudKit integration is store-level, not per-record.
/// This service keeps the SwiftData store local-only and mirrors opted-in records to CloudKit.
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    /// CloudKit record type used for MedicalRecord mirrors.
    /// IMPORTANT:
    /// - CloudKit schemas are environment-specific (Development vs Production).
    /// - You can't create new record types in the Production schema from the client.
    ///   If you see: "Cannot create new type … in production schema",
    ///   create the record type in the CloudKit Dashboard (Development), then deploy to Production.
    private let medicalRecordType = "MedicalRecord"

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    // MARK: - Sync

    func syncIfNeeded(record: MedicalRecord) async throws {
        guard record.isCloudEnabled else { return }

        let status = try await accountStatus()
        guard status == .available else {
            throw NSError(
                domain: "CloudSyncService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status))."]
            )
        }

        let recordName = record.cloudRecordName ?? record.uuid
        let ckID = CKRecord.ID(recordName: recordName)

        let ckRecord: CKRecord
        do {
            ckRecord = try await database.record(for: ckID)
        } catch {
            // If it doesn't exist yet, create a new one.
            ckRecord = CKRecord(recordType: medicalRecordType, recordID: ckID)
        }

        applyMedicalRecord(record, to: ckRecord)

        let saved = try await database.save(ckRecord)

        // Persist back CloudKit identity
        record.cloudRecordName = saved.recordID.recordName
    }

    func disableCloud(for record: MedicalRecord) {
        record.isCloudEnabled = false
        // Keep cloudRecordName so it can be re-enabled later without duplicating, if desired.
    }

    // MARK: - Sharing

    func createShare(for record: MedicalRecord) async throws -> CKShare {
        // Ensure record exists in CloudKit
        try await syncIfNeeded(record: record)

        let recordName = record.cloudRecordName ?? record.uuid
        let rootID = CKRecord.ID(recordName: recordName)
        let root = try await database.record(for: rootID)

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Shared Medical Record" as CKRecordValue

        let modify = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
        modify.savePolicy = .changedKeys

        do {
            try await withCheckedThrowingContinuation { cont in
                modify.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        print("[CloudSyncService] Successfully created CKShare for record=\(record.uuid)")
                        cont.resume(returning: ())
                    case .failure(let error):
                        print("[CloudSyncService] Failed to create CKShare for record=\(record.uuid): \(error)")
                        cont.resume(throwing: self.enrichCloudKitError(error))
                    }
                }
                self.database.add(modify)
            }

            // Re-fetch the saved share record from the server to ensure server-generated fields are populated
            let savedShareRecord = try await database.record(for: share.recordID)
            if let savedShare = savedShareRecord as? CKShare {
                print("[CloudSyncService] Re-fetched CKShare record. url=\(String(describing: savedShare.url))")
                return savedShare
            } else {
                // Shouldn't happen, but return the original share if casting fails
                return share
            }
        } catch {
            throw enrichCloudKitError(error)
        }
    }

    /// iOS 17+ sharing: create the CKShare and return a `UIActivityViewController` configured with the share URL.
    func makeShareActivityController(for record: MedicalRecord, onComplete: @escaping (Result<URL?, Error>) -> Void) async throws -> UIViewController {
        // Ensure iCloud account available
        let status = try await container.accountStatus()
        guard status == .available else {
            let err = NSError(domain: "CloudSyncService", code: 3, userInfo: [NSLocalizedDescriptionKey: "iCloud account not available (status: \(status)). Please sign in to iCloud."])
            ShareDebugStore.shared.appendLog("makeShareActivityController: account not available: \(status)")
            throw err
        }

        // Create the share (ensures record exists and CKShare is created on server)
        let share = try await createShare(for: record)

        guard let url = share.url else {
            let err = NSError(domain: "CloudSyncService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Share created but no URL available. Ensure CloudKit schema and account are configured."])
            ShareDebugStore.shared.appendLog("makeShareActivityController: created share but no URL for record=\(record.uuid)")
            throw err
        }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.permittedArrowDirections = []
        activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            if let activityError = activityError {
                ShareDebugStore.shared.appendLog("makeShareActivityController: activity error=\(activityError)")
                onComplete(.failure(activityError))
            } else if completed {
                ShareDebugStore.shared.appendLog("makeShareActivityController: activity completed for record=\(record.uuid) activity=\(String(describing: activityType))")
                onComplete(.success(url))
            } else {
                ShareDebugStore.shared.appendLog("makeShareActivityController: activity cancelled")
                onComplete(.success(nil))
            }
        }

        return activityVC
    }

    // MARK: - Deletion

    // Convenience compatibility wrapper for earlier API name
    func deleteCloudRecord(for record: MedicalRecord) async throws {
        try await deleteSyncRecord(forLocalRecord: record)
    }

    func deleteSyncRecord(forLocalRecord record: MedicalRecord) async throws {
        let recordName = record.cloudRecordName ?? record.uuid
        let ckID = CKRecord.ID(recordName: recordName)

        // First try to delete by record ID directly
        do {
            let deleted = try await database.deleteRecord(withID: ckID)
            print("[CloudSyncService] Deleted CloudKit record id=\(deleted.recordName) for local record=\(record.uuid)")
            return
        } catch {
            print("[CloudSyncService] Direct delete failed for CloudKit record id=\(ckID.recordName): \(error)")
            // Try to enrich and rethrow the error
            // We'll fall through to fallback query approach instead of rethrowing here
        }

        // Fallback: delete by matching uuid field
        let predicate = NSPredicate(format: "uuid == %@", record.uuid)
        let query = CKQuery(recordType: medicalRecordType, predicate: predicate)

        // Run the query operation and collect matched record IDs using a continuation
        let idsToDelete: [CKRecord.ID] = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord.ID], Error>) in
            var foundIDs: [CKRecord.ID] = []
            let op = CKQueryOperation(query: query)
            op.recordMatchedBlock = { (matchedID: CKRecord.ID, matchedResult: Result<CKRecord, Error>) in
                switch matchedResult {
                case .success(let rec): foundIDs.append(rec.recordID)
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }
            op.queryResultBlock = { (result: Result<CKQueryOperation.Cursor?, Error>) in
                switch result {
                case .success(_): cont.resume(returning: foundIDs)
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            database.add(op)
        }

        if !idsToDelete.isEmpty {
            // Delete found records (can delete multiple matches just in case)
            for id in idsToDelete {
                do {
                    let deleted = try await database.deleteRecord(withID: id)
                    print("[CloudSyncService] Deleted CloudKit record id=\(deleted.recordName) via uuid match for local uuid=\(record.uuid)")
                } catch {
                    print("[CloudSyncService] Failed to delete matched CloudKit record id=\(id.recordName): \(error)")
                    throw enrichCloudKitError(error)
                }
            }
        } else {
            // nothing found to delete - not an error
            print("[CloudSyncService] No CloudKit record found matching uuid=\(record.uuid)")
        }
    }

    // MARK: - Mapping

    private func applyMedicalRecord(_ record: MedicalRecord, to ckRecord: CKRecord) {
        ckRecord["uuid"] = record.uuid as NSString
        ckRecord["createdAt"] = record.createdAt as NSDate
        ckRecord["updatedAt"] = record.updatedAt as NSDate

        ckRecord["isPet"] = record.isPet as NSNumber

        ckRecord["personalFamilyName"] = record.personalFamilyName as NSString
        ckRecord["personalGivenName"] = record.personalGivenName as NSString
        ckRecord["personalNickName"] = record.personalNickName as NSString
        ckRecord["personalGender"] = record.personalGender as NSString
        if let birthdate = record.personalBirthdate {
            ckRecord["personalBirthdate"] = birthdate as NSDate
        } else {
            ckRecord["personalBirthdate"] = nil
        }

        ckRecord["personalSocialSecurityNumber"] = record.personalSocialSecurityNumber as NSString
        ckRecord["personalAddress"] = record.personalAddress as NSString
        ckRecord["personalHealthInsurance"] = record.personalHealthInsurance as NSString
        ckRecord["personalHealthInsuranceNumber"] = record.personalHealthInsuranceNumber as NSString
        ckRecord["personalEmployer"] = record.personalEmployer as NSString

        ckRecord["personalName"] = record.personalName as NSString
        ckRecord["personalAnimalID"] = record.personalAnimalID as NSString
        ckRecord["ownerName"] = record.ownerName as NSString
        ckRecord["ownerPhone"] = record.ownerPhone as NSString
        ckRecord["ownerEmail"] = record.ownerEmail as NSString

        ckRecord["emergencyName"] = record.emergencyName as NSString
        ckRecord["emergencyNumber"] = record.emergencyNumber as NSString
        ckRecord["emergencyEmail"] = record.emergencyEmail as NSString

        // Simple versioning to allow future schema changes
        ckRecord["schemaVersion"] = 1 as NSNumber
    }

    private func enrichCloudKitError(_ error: Error) -> Error {
        // Try to map common CKError codes to friendlier messages
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Not signed in to iCloud. Please sign in and try again."])
            case .permissionFailure:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Permission failure. Check CloudKit dashboard roles and container permissions."])
            case .serverRejectedRequest:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "Server rejected request. Try again later."])
            case .zoneNotFound:
                return NSError(domain: "CloudSyncService", code: ck.code.rawValue, userInfo: [NSLocalizedDescriptionKey: "CloudKit zone not found. Ensure your CloudKit schema and zone are set up."])
            default:
                break
            }
        }
        return error
    }
}
