import SwiftUI
import CloudKit

/// Minimal UI to create a CKShare for a MedicalRecord.
///
/// This is a SwiftUI-only MVP: it creates the share and then shows the share URL.
/// (A full UICloudSharingController integration can be added next.)
struct CloudShareSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This will create a CloudKit share for this record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let shareURL {
                    Section("Share") {
                        Text(shareURL.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)

                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await createShare() }
                    } label: {
                        if isBusy {
                            ProgressView()
                        } else {
                            Text("Create Share")
                        }
                    }
                    .disabled(isBusy)
                }
            }
            .navigationTitle("Share Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func createShare() async {
        errorMessage = nil
        shareURL = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let share = try await CloudSyncService.shared.createShare(for: record)
            shareURL = share.url
            if shareURL == nil {
                errorMessage = "Share created, but no share URL available. (This can happen in Simulator or if iCloud isn't configured.)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
