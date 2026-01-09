import SwiftUI
import SwiftData

struct CloudRecordSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("cloudEnabled") private var cloudEnabled: Bool = false

    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    @State private var syncingRecordID: String?
    @State private var errorMessage: String?
    @State private var sharingRecord: MedicalRecord?

    var body: some View {
        Form {
            Section("Cloud") {
                Toggle("Enable iCloud Sync (per-record opt-in)", isOn: $cloudEnabled)

                Text("When enabled, you can choose which records are synced to iCloud and which are shared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Records") {
                if records.isEmpty {
                    Text("No records yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(records) { record in
                        recordRow(for: record)
                    }
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("iCloud")
        .sheet(item: $sharingRecord) { record in
            CloudShareSheet(record: record)
        }
    }

    @ViewBuilder
    private func recordRow(for record: MedicalRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayName(for: record))
                    .font(.headline)
                Spacer()

                Image(systemName: cloudStatusIcon(for: record))
                    .foregroundStyle(cloudStatusColor(for: record))
            }

            Toggle("Sync", isOn: Binding(
                get: { record.isCloudEnabled },
                set: { newValue in
                    record.isCloudEnabled = newValue
                    if !newValue {
                        record.isCloudShared = false
                    }
                    record.updatedAt = Date()
                    try? modelContext.save()
                }
            ))
            .disabled(!cloudEnabled)

            HStack {
                Button("Sync Now") {
                    Task { await syncNow(record) }
                }
                .disabled(!cloudEnabled || !record.isCloudEnabled || syncingRecordID == record.id)

                Spacer()

                Button("Share") {
                    sharingRecord = record
                }
                .disabled(!cloudEnabled || !record.isCloudEnabled)
            }
            .font(.subheadline)

            if !cloudEnabled {
                Text("Enable iCloud Sync above to manage per-record syncing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @MainActor
    private func syncNow(_ record: MedicalRecord) async {
        errorMessage = nil
        syncingRecordID = record.id
        defer { syncingRecordID = nil }

        do {
            try modelContext.save()
            try await CloudSyncService.shared.syncIfNeeded(record: record)
            try modelContext.save()
        } catch {
            errorMessage = "Cloud sync failed: \(error.localizedDescription)"
        }
    }

    private func displayName(for record: MedicalRecord) -> String {
        if record.isPet {
            let name = record.personalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
            return "Pet"
        } else {
            let family = record.personalFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let given = record.personalGivenName.trimmingCharacters(in: .whitespacesAndNewlines)
            let nick = record.personalNickName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !nick.isEmpty { return nick }
            if family.isEmpty && given.isEmpty { return "Person" }
            return [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    private func cloudStatusIcon(for record: MedicalRecord) -> String {
        if record.isCloudEnabled {
            return record.isCloudShared ? "person.2.circle" : "icloud"
        }
        return "iphone"
    }

    private func cloudStatusColor(for record: MedicalRecord) -> Color {
        if record.isCloudEnabled {
            return record.isCloudShared ? .green : .blue
        }
        return .secondary
    }
}

#Preview {
    NavigationStack {
        CloudRecordSettingsView()
    }
    .modelContainer(for: MedicalRecord.self, inMemory: true)
}
