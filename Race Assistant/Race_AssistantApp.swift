//
//  Race_AssistantApp.swift
//  Race Assistant
//
//  Created by Petr on 21.08.2026.
//

import SwiftUI
import SwiftData

@main
struct Race_AssistantApp: App {

    var sharedModelContainer: ModelContainer {
        AppModelContainer.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    let context = sharedModelContainer.mainContext

                    DefaultReferenceData.seedIfNeeded(
                        modelContext: context
                    )

                    SeedDataImporter.importIfNeeded(
                        modelContext: context
                    )
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
