import Foundation
import CloudKit

@MainActor
final class CloudKitSharePermissionService {
    static let shared = CloudKitSharePermissionService()

    enum EffectivePermission { case unknown, readOnly, readWrite }

    private let containerIdentifier = AppConfig.CloudKit.containerID
    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    // Keep in sync with CloudSyncService.shareZoneName
    private let shareZoneName = AppConfig.CloudKit.shareZoneName
    private var shareZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: shareZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private init() {}

    func permission(for record: MedicalRecord) async -> EffectivePermission {
        guard let shareName = record.cloudShareRecordName, !shareName.isEmpty else {
            return record.isSharingEnabled ? .readWrite : .unknown
        }

        do {
            let db = container.privateCloudDatabase
            let shareID = CKRecord.ID(recordName: shareName, zoneID: shareZoneID)
            let fetched = try await db.record(for: shareID)
            guard let share = fetched as? CKShare else { return .unknown }

            // Determine this device's participant permission.
            // Find the participant matching the current user identity if available.
            // If not resolvable, fall back to the first accepted participant.
            var effective: EffectivePermission = .unknown

            if let myRecordID = try? await container.userRecordID() {
                if let mine = share.participants.first(where: { $0.userIdentity.userRecordID == myRecordID }) {
                    switch mine.permission {
                    case .readOnly: effective = .readOnly
                    case .readWrite: effective = .readWrite
                    default: break
                    }
                }
            }

            if effective == .unknown {
                if share.participants.contains(where: { $0.permission == .readWrite && $0.acceptanceStatus == .accepted }) {
                    effective = .readWrite
                } else if !share.participants.isEmpty {
                    effective = .readOnly
                }
            }

            return effective
        } catch {
            ShareDebugStore.shared.appendLog("CloudKitSharePermissionService: permission fetch failed for share=\(shareName): \(error)")
            return .unknown
        }
    }
}
