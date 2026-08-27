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

    var sharedModelContainer: ModelContainer = {

        let schema = Schema([
            Championship.self,
            Season.self,
            Stage.self,
            ScheduleEvent.self,
            Circuit.self,
            Role.self,
            RaceClass.self,
            EventRole.self,
            EventClass.self,
        ])

        let modelConfiguration =
            ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [
                    modelConfiguration
                ]
            )
        } catch {
            fatalError(
                "Could not create ModelContainer: \(error)"
            )
        }
    }()

    var body: some Scene {

        WindowGroup {

            ContentView()
                .task {

                    let context =
                        sharedModelContainer
                            .mainContext

                    // Сначала создаём стандартные
                    // справочники приложения.
                    DefaultReferenceData
                        .seedIfNeeded(
                            modelContext:
                                context
                        )

                    // Затем импортируем расширенный
                    // dataset и расписание.
                    //
                    // SeedDataImporter сам проверяет
                    // версию импорта и повторно
                    // данные не создаёт.
                    SeedDataImporter
                        .importIfNeeded(
                            modelContext:
                                context
                        )
                }
        }
        .modelContainer(
            sharedModelContainer
        )
    }
}
