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
    @Query(sort: \MedicalRecord.updatedAt, order: .reverse) private var records: [MedicalRecord]

    var body: some View {
        VStack {
            // Diagnostic label to confirm ContentView is mounted
            Text("MyHealthData — ContentView loaded")
                .font(.headline)
                .padding(8)

            RecordListView()
        }
        .onAppear {
            // Keep DEBUG-only sample insertion to help with UI during development.
            #if DEBUG
            if records.isEmpty {
                let sample = MedicalRecord()
                sample.updatedAt = Date()
                sample.personalNickName = "Debug User"
                modelContext.insert(sample)
            }
            #endif
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: MedicalRecord.self, inMemory: true)
}
