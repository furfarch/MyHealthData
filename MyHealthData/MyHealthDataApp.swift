//
//  MyHealthDataApp.swift
//  MyHealthData
//
//  Created by Chris Furfari on 05.01.2026.
//

import SwiftUI
import SwiftData

@main
struct MyHealthDataApp: App {
    private let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase: ScenePhase

    // Keep a single fetcher instance alive for the app lifetime so its async
    // query operations won't be deallocated before completion (this was causing
    // `no modelContext set` and imports being skipped).
    private let cloudFetcher: CloudKitMedicalRecordFetcher

    init() {
        let schema = Schema([
            MedicalRecord.self,
            BloodEntry.self,
            DrugEntry.self,
            VaccinationEntry.self,
            AllergyEntry.self,
            IllnessEntry.self,
            RiskEntry.self,
            MedicalHistoryEntry.self,
            MedicalDocumentEntry.self,
            EmergencyContact.self,
            WeightEntry.self
        ])

        // Force a purely local store. This avoids Core Data's CloudKit validation rules
        // from preventing the app from launching while the schema is still evolving.
        // (You can re-enable CloudKit later with a dedicated migration pass.)
        let localConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        // Initialize the retained fetcher early so it's available in tasks
        self.cloudFetcher = CloudKitMedicalRecordFetcher(containerIdentifier: "iCloud.com.furfarch.MyHealthData")

        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            // LOG THE ERROR so we know why persistent store failed
            print("[MyHealthDataApp] Failed to create persistent ModelContainer: \(error)")
            let memoryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            self.modelContainer = try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // On first launch, attempt to pull records from CloudKit into the local store.
                    // Keep the fetcher retained on self so its async callbacks can import safely.
                    self.cloudFetcher.setModelContext(self.modelContainer.mainContext)
                    self.cloudFetcher.fetchAll()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Use two-argument onChange to satisfy the newer API and avoid deprecation warnings.
            if newPhase == .active {
                Task { @MainActor in
                    self.cloudFetcher.setModelContext(self.modelContainer.mainContext)
                    self.cloudFetcher.fetchAll()
                }
            }
        }
    }
}
