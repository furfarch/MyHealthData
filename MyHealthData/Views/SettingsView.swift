import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var accountStatus: CKAccountStatus?
    @State private var accountStatusError: String?

    // Export UI state
    @State private var showExportSheet: Bool = false
    @State private var exportItems: [Any] = []

    // Import Share URL state
    @State private var importShareURL: String = ""
    @State private var isImportingShare: Bool = false
    @State private var importResultMessage: String?
    @State private var showImportResultAlert: Bool = false

    private let containerIdentifier = "iCloud.com.furfarch.MyHealthData"

    // Display settings
    @AppStorage("recordViewerStyle") private var viewerStyle: String = "cards"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ExportSettingsView()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                Section("iCloud") {
                    NavigationLink {
                        CloudRecordSettingsView()
                    } label: {
                        Label("iCloud Sync and Sharing of Records", systemImage: "icloud")
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(accountStatus.map(accountStatusText) ?? "Checking…")
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

                    // Always-available export for TestFlight / Release: copies logs and opens share sheet
                    Button(action: {
                        let export = ShareDebugStore.shared.exportText()

                        #if canImport(UIKit)
                        // Copy to clipboard
                        UIPasteboard.general.string = export

                        // Also write to a temporary file and share the file URL (more reliable than sharing a huge String)
                        let fileURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("MyHealthData-ShareLogs-\(Int(Date().timeIntervalSince1970)).txt")
                        do {
                            try export.write(to: fileURL, atomically: true, encoding: .utf8)
                            exportItems = [fileURL]
                        } catch {
                            // Fallback to sharing plain text if file write fails
                            exportItems = [export]
                        }
                        #elseif canImport(AppKit)
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(export, forType: .string)
                        exportItems = [export]
                        #endif

                        ShareDebugStore.shared.appendLog("User initiated export from Settings")
                        showExportSheet = true
                    }) {
                        Label("Export Share Logs", systemImage: "square.and.arrow.up.on.square")
                    }

                    // Import Share URL UI (minimal)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import Share URL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("Paste iCloud share URL here", text: $importShareURL)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)

                        HStack {
                            Button(action: {
                                guard !importShareURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                      let url = URL(string: importShareURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                                    importResultMessage = "Invalid URL"
                                    showImportResultAlert = true
                                    return
                                }

                                isImportingShare = true
                                Task { @MainActor in
                                    await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                                    isImportingShare = false
                                    importResultMessage = "Imported (check logs for details)"
                                    showImportResultAlert = true
                                }
                            }) {
                                if isImportingShare {
                                    ProgressView()
                                } else {
                                    Text("Import")
                                }
                            }

                            Button("Clear") {
                                importShareURL = ""
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await refreshAccountStatus()
            }
            .sheet(isPresented: $showExportSheet) {
                ActivityViewController(items: exportItems)
                    .onAppear {
                        ShareDebugStore.shared.appendLog("Export sheet presented (items=\(exportItems.count))")
                    }
            }
            .alert(importResultMessage ?? "", isPresented: $showImportResultAlert) {
                Button("OK", role: .cancel) {}
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
                #endif
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
