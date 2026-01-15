import Foundation
import CloudKit
import SwiftData

/// Accepts a CloudKit share invitation and then triggers a refresh from the Shared database.
@MainActor
final class CloudKitShareAcceptanceService {
    static let shared = CloudKitShareAcceptanceService()

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    private init() {}

    func acceptShare(from url: URL, modelContext: ModelContext) async {
        ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: acceptShare url=\(url.absoluteString)")

        do {
            let metadata = try await fetchShareMetadata(for: url)
            try await acceptShareMetadata(metadata)

            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: accepted share, importing shared records")

            // Import the root record (and potentially descendants later) into SwiftData.
            let rootIDs: [CKRecord.ID] = [metadata.rootRecordID]
            let database = container.sharedCloudDatabase
            let recordsByID = try await fetchRecords(by: rootIDs, from: database)

            // Best-effort: also fetch the share itself so we can show participants.
            var fetchedShare: CKShare?
            do {
                let shareByID = try await fetchRecords(by: [metadata.share.recordID], from: database)
                fetchedShare = shareByID[metadata.share.recordID] as? CKShare
            } catch {
                // not fatal
                ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: unable to fetch CKShare for participants: \(error)")
            }

            CloudKitSharedImporter.upsertSharedMedicalRecords(
                recordsByID.values,
                share: fetchedShare,
                modelContext: modelContext
            )

            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: import complete (count=\(recordsByID.count))")
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: accept failed error=\(error)")
            ShareDebugStore.shared.lastError = error
        }
    }

    private func fetchShareMetadata(for url: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CKShare.Metadata, Error>) in
            let op = CKFetchShareMetadataOperation(shareURLs: [url])
            var captured: CKShare.Metadata?

            op.perShareMetadataResultBlock = { _, result in
                switch result {
                case .success(let md):
                    captured = md
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            op.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let md = captured {
                        cont.resume(returning: md)
                    } else {
                        cont.resume(throwing: NSError(domain: "CloudKitShareAcceptanceService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No share metadata returned."]))
                    }
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }

    private func acceptShareMetadata(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated

            op.perShareResultBlock = { md, result in
                switch result {
                case .success(let share):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare success share=\(share.recordID.recordName) container=\(md.containerIdentifier)")
                case .failure(let err):
                    ShareDebugStore.shared.appendLog("CloudKitShareAcceptanceService: perShare error=\(err)")
                }
            }

            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: ())
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            self.container.add(op)
        }
    }

    private func fetchRecords(by ids: [CKRecord.ID], from database: CKDatabase) async throws -> [CKRecord.ID: CKRecord] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CKRecord.ID: CKRecord], Error>) in
            let op = CKFetchRecordsOperation(recordIDs: ids)
            var fetched: [CKRecord.ID: CKRecord] = [:]

            op.perRecordResultBlock = { recordID, result in
                if case .success(let rec) = result { fetched[recordID] = rec }
            }

            op.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: fetched)
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }

            database.add(op)
        }
    }
}

// MARK: - Importer

@MainActor
private enum CloudKitSharedImporter {
    static func upsertSharedMedicalRecords(_ ckRecords: some Sequence<CKRecord>, share: CKShare?, modelContext: ModelContext) {
        for ckRecord in ckRecords {
            guard ckRecord.recordType == "MedicalRecord" else { continue }
            guard let uuid = ckRecord["uuid"] as? String else { continue }

            let fetchDescriptor = FetchDescriptor<MedicalRecord>(predicate: #Predicate { $0.uuid == uuid })
            let existing = (try? modelContext.fetch(fetchDescriptor))?.first
            let record = existing ?? MedicalRecord(uuid: uuid)

            record.createdAt = ckRecord["createdAt"] as? Date ?? record.createdAt
            record.updatedAt = (ckRecord["updatedAt"] as? Date) ?? record.updatedAt

            record.personalFamilyName = ckRecord["personalFamilyName"] as? String ?? ""
            record.personalGivenName = ckRecord["personalGivenName"] as? String ?? ""
            record.personalNickName = ckRecord["personalNickName"] as? String ?? ""
            record.personalGender = ckRecord["personalGender"] as? String ?? ""
            record.personalBirthdate = ckRecord["personalBirthdate"] as? Date
            record.personalSocialSecurityNumber = ckRecord["personalSocialSecurityNumber"] as? String ?? ""
            record.personalAddress = ckRecord["personalAddress"] as? String ?? ""
            record.personalHealthInsurance = ckRecord["personalHealthInsurance"] as? String ?? ""
            record.personalHealthInsuranceNumber = ckRecord["personalHealthInsuranceNumber"] as? String ?? ""
            record.personalEmployer = ckRecord["personalEmployer"] as? String ?? ""

            if let boolVal = ckRecord["isPet"] as? Bool {
                record.isPet = boolVal
            } else if let num = ckRecord["isPet"] as? NSNumber {
                record.isPet = num.boolValue
            }

            record.personalName = ckRecord["personalName"] as? String ?? ""
            record.personalAnimalID = ckRecord["personalAnimalID"] as? String ?? ""
            record.ownerName = ckRecord["ownerName"] as? String ?? ""
            record.ownerPhone = ckRecord["ownerPhone"] as? String ?? ""
            record.ownerEmail = ckRecord["ownerEmail"] as? String ?? ""
            record.emergencyName = ckRecord["emergencyName"] as? String ?? ""
            record.emergencyNumber = ckRecord["emergencyNumber"] as? String ?? ""
            record.emergencyEmail = ckRecord["emergencyEmail"] as? String ?? ""

            record.isCloudEnabled = true
            record.isSharingEnabled = true
            record.cloudRecordName = ckRecord.recordID.recordName

            if let shareRef = ckRecord.share {
                record.cloudShareRecordName = shareRef.recordID.recordName
            } else {
                record.cloudShareRecordName = share?.recordID.recordName
            }

            if let share {
                record.shareParticipantsSummary = participantsSummary(from: share)
            }

            if existing == nil {
                modelContext.insert(record)
            }
        }

        do {
            try modelContext.save()
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharedImporter: failed saving import: \(error)")
        }
    }

    private static func participantsSummary(from share: CKShare) -> String {
        let participants = share.participants
        if participants.isEmpty { return "Only you" }

        // Show a compact list: email if present, else user recordName.
        let parts: [String] = participants.compactMap { p in
            if let email = p.userIdentity.lookupInfo?.emailAddress, !email.isEmpty {
                return email
            }
            let name = p.userIdentity.userRecordID?.recordName
            return name
        }
        return parts.isEmpty ? "Participants" : parts.joined(separator: ", ")
    }
}
