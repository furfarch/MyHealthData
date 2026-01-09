import SwiftUI
import CloudKit

struct SettingsView: View {
    @State private var accountStatus: CKAccountStatus?
    @State private var accountStatusError: String?

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CloudRecordSettingsView()
                } label: {
                    Label("iCloud", systemImage: "icloud")
                }

                Section("Diagnostics") {
                    LabeledContent("Container", value: containerIdentifier)

                    if let accountStatus {
                        LabeledContent("Account", value: accountStatusText(accountStatus))
                    } else {
                        Text("Checking iCloud status…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let accountStatusError {
                        Text(accountStatusError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Re-check iCloud Status") {
                        Task { await refreshAccountStatus() }
                    }

                    Text("Simulator note: if the Simulator isn't signed into iCloud, CloudKit will show 'No iCloud account'.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Console messages") {
                    Text("Messages like CA Event failures are iOS Simulator system logs and can be ignored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshAccountStatus()
            }
        }
    }

    private func refreshAccountStatus() async {
        accountStatusError = nil
        do {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            accountStatus = status
        } catch {
            accountStatus = nil
            accountStatusError = "iCloud status check failed: \(error.localizedDescription)"
        }
    }

    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            return "Available"
        case .noAccount:
            return "No iCloud account"
        case .restricted:
            return "Restricted"
        case .couldNotDetermine:
            return "Could not determine"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    SettingsView()
}
