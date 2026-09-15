import SwiftUI
import SwiftData

struct ChampionshipClassesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RaceClass.name) private var classes: [RaceClass]
    let championship: Championship
    @State private var errorMessage: String?
    var body: some View {
        List {
            Section {
                ForEach(classes) { item in
                    Toggle(item.shortName.isEmpty ? item.name : item.shortName, isOn: Binding(
                        get: { championship.raceClasses.contains { $0 === item } },
                        set: { selected in
                            if selected { championship.raceClasses.append(item) }
                            else { championship.raceClasses.removeAll { $0 === item } }
                            championship.classesConfigured = true
                            do { try modelContext.save() }
                            catch { modelContext.rollback(); errorMessage = error.localizedDescription }
                        }
                    ))
                }
            } footer: { Text("В событиях этого соревнования доступны только выбранные классы. Если классы не нужны, снимите все отметки. Классы существующих событий сохраняются.") }
        }
        .navigationTitle("Классы соревнования")
        .alert("Ошибка сохранения", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
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
