import SwiftUI
import SwiftData

struct ChampionshipClassesView: View {
    let championship: Championship
    var body: some View { ClassAssignmentView(championship: championship) }
}

@MainActor
enum ChampionshipClassSetup {
    static func configure(_ context: ModelContext) {
        do {
            for championship in try context.fetch(FetchDescriptor<Championship>()) where !championship.classesConfigured {
                let used = championship.seasons.flatMap(\.stages).flatMap(\.scheduleEvents)
                    .flatMap(\.eventClasses).compactMap(\.raceClass)
                var seen = Set<PersistentIdentifier>()
                championship.raceClasses = used.filter { seen.insert($0.persistentModelID).inserted }
                championship.classesConfigured = true
            }
            try context.save()
        } catch { context.rollback(); print("Классы соревнований: \(error)") }
    }
}
