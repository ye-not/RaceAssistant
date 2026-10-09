import SwiftUI
import SwiftData

struct StageClassesSection: View {
    let stage: Stage
    var body: some View {
        Section {
            NavigationLink { ClassAssignmentView(championship: stage.season?.championship, stage: stage) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Классы этапа")
                    Text(stage.availableClasses.map { $0.shortName.isEmpty ? $0.name : $0.shortName }.sorted().joined(separator: " · ").isEmpty
                        ? "Не выбраны" : stage.availableClasses.map { $0.shortName.isEmpty ? $0.name : $0.shortName }.sorted().joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ClassAssignmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RaceClass.name) private var allClasses: [RaceClass]
    let championship: Championship?
    let stage: Stage?
    @State private var selection: [RaceClass]
    @State private var search = ""
    @State private var adding = false
    @State private var error: String?
    init(championship: Championship?, stage: Stage? = nil) {
        self.championship = championship; self.stage = stage
        _selection = State(initialValue: stage?.availableClasses ?? championship?.raceClasses ?? [])
    }
    private var seriesClasses: [RaceClass] { championship?.raceClasses ?? [] }
    private func visible(_ value: RaceClass) -> Bool {
        (value.active || selection.contains { $0 === value }) &&
        (search.isEmpty || value.name.localizedCaseInsensitiveContains(search) || value.shortName.localizedCaseInsensitiveContains(search))
    }
    var body: some View {
        List {
            Section("Классы серии") {
                ForEach(seriesClasses.filter(visible).sorted { $0.name < $1.name }) { item in row(item) }
                if seriesClasses.isEmpty { Text("Пока не привязаны").foregroundStyle(.secondary) }
            }
            Section("Другие классы справочника") {
                ForEach(allClasses.filter { item in !seriesClasses.contains { $0 === item } && visible(item) }) { item in row(item) }
            }
            Section {
                Button("Добавить новый класс…", systemImage: "plus") { adding = true }
            } footer: { Text("Дополнительные классы привязываются к серии и этому этапу. Ранее созданные этапы и строки расписания не меняются.") }
        }
        .navigationTitle(stage == nil ? "Классы серии" : "Классы этапа")
        .searchable(text: $search, prompt: "Класс или сокращение")
        .toolbar { Button("Сохранить") { save() } }
        .sheet(isPresented: $adding) {
            AddRaceClassView { item in
                if !selection.contains(where: { $0 === item }) { selection.append(item) }
                if let championship, !championship.raceClasses.contains(where: { $0 === item }) {
                    championship.raceClasses.append(item); championship.classesConfigured = true
                    do { try modelContext.save() } catch { modelContext.rollback(); self.error = error.localizedDescription }
                }
            }
        }
        .alert("Ошибка сохранения", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private func row(_ item: RaceClass) -> some View {
        Toggle(item.name + (item.active ? "" : " (архив)"), isOn: Binding(
            get: { selection.contains { $0 === item } },
            set: { selected in
                if selected { if !selection.contains(where: { $0 === item }) { selection.append(item) } }
                else { selection.removeAll { $0 === item } }
            }
        ))
    }
    private func save() {
        if let stage {
            stage.raceClasses = selection; stage.classesConfigured = true
            if let championship {
                for item in selection where !championship.raceClasses.contains(where: { $0 === item }) { championship.raceClasses.append(item) }
                championship.classesConfigured = true
            }
        } else if let championship {
            championship.raceClasses = selection; championship.classesConfigured = true
        }
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); self.error = error.localizedDescription }
    }
}

@MainActor
enum StageClassSetup {
    static func configure(_ context: ModelContext) {
        do {
            for stage in try context.fetch(FetchDescriptor<Stage>()) where !stage.classesConfigured {
                let used = stage.scheduleEvents.flatMap(\.eventClasses).compactMap(\.raceClass)
                var seen = Set<PersistentIdentifier>()
                stage.raceClasses = (used.isEmpty ? (stage.season?.championship?.raceClasses ?? []) : used)
                    .filter { seen.insert($0.persistentModelID).inserted }
                stage.classesConfigured = true
            }
            try context.save()
        } catch { context.rollback(); print("Классы этапов: \(error)") }
    }
}
