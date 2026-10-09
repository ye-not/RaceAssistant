import SwiftData

@MainActor
enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            Championship.self,
            Season.self,
            Stage.self,
            ScheduleEvent.self,
            Circuit.self,
            CircuitConfiguration.self,
            Role.self,
            RaceClass.self,
            EventRole.self,
            EventClass.self,
            SafetyCarPeriod.self,
            RaceInterruption.self,
            StewardIncident.self,
            StewardIncidentTask.self,
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
