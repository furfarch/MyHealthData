import SwiftUI
import CloudKit
import UIKit

struct CloudShareSheet: View {
    let record: MedicalRecord

    @Environment(\.dismiss) private var dismiss

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showShareSheet = false
    @State private var shareController: UIViewController?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this record using iCloud. You can invite others and manage permissions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section("Error") { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await presentShareSheet_iOS() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Share Record") }
                    }
                }
                .background(
                    ShareSheetPresenter(controller: $shareController, isPresented: $showShareSheet)
                )
            }
            .navigationTitle("Share Record")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    @MainActor
    private func presentShareSheet_iOS() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let controller = try await CloudSyncService.shared.makeShareActivityController(for: record) { result in
                DispatchQueue.main.async {
                    self.showShareSheet = false
                    switch result {
                    case .success:
                        self.errorMessage = nil
                    case .failure(let err):
                        self.errorMessage = err.localizedDescription
                    }
                }
            }
            shareController = controller
            showShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    struct ShareSheetPresenter: UIViewControllerRepresentable {
        @Binding var controller: UIViewController?
        @Binding var isPresented: Bool
        func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            guard isPresented, let controller else { return }
            if uiViewController.presentedViewController == nil {
                uiViewController.present(controller, animated: true) { isPresented = false }
            }
        }
    }
}
