//
//  ContentView.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    // Show alert when a share is accepted and imported
    @State private var showShareAcceptedAlert: Bool = false
    @State private var importedName: String = ""

    var body: some View {
        RecordListView()
            .onOpenURL { url in
                // Accept CloudKit share links and import shared records.
                Task { @MainActor in
                    await CloudKitShareAcceptanceService.shared.acceptShare(from: url, modelContext: modelContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: CloudKitShareAcceptanceService.didAcceptShareNotification)) { notif in
                if let userInfo = notif.userInfo, let names = userInfo["names"] as? [String], let first = names.first {
                    importedName = first
                } else {
                    importedName = "record"
                }
                showShareAcceptedAlert = true
            }
            .alert("Imported", isPresented: $showShareAcceptedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(importedName) imported")
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
