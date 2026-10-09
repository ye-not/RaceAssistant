import SwiftUI
import SwiftData

struct AddRaceClassView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var classes: [RaceClass]
    let raceClass: RaceClass?
    let onCreated: (RaceClass) -> Void
    @State private var name: String
    @State private var shortName: String
    @State private var archived: Bool
    @State private var error: String?
    init(raceClass: RaceClass? = nil, onCreated: @escaping (RaceClass) -> Void = { _ in }) {
        self.raceClass = raceClass; self.onCreated = onCreated
        _name = State(initialValue: raceClass?.name ?? "")
        _shortName = State(initialValue: raceClass?.shortName ?? "")
        _archived = State(initialValue: !(raceClass?.active ?? true))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Класс") {
                    TextField("Название", text: $name)
                    TextField("Сокращение", text: $shortName)
                }
                Section {
                    Toggle("В архиве", isOn: $archived)
                } footer: { Text("Архивный класс сохраняется в прежних расписаниях, но не предлагается при добавлении новых событий.") }
            }
            .navigationTitle(raceClass == nil ? "Новый класс" : "Редактировать класс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !classes.contains(where: { $0 !== raceClass && ($0.name.caseInsensitiveCompare(title) == .orderedSame || (!code.isEmpty && $0.shortName.caseInsensitiveCompare(code) == .orderedSame)) }) else {
            error = "Класс с таким названием или сокращением уже есть в справочнике."; return
        }
        let value = raceClass ?? RaceClass(name: title)
        if raceClass == nil { modelContext.insert(value) }
        value.name = title; value.shortName = code; value.active = !archived
        do { try modelContext.save(); onCreated(value); dismiss() }
        catch { modelContext.rollback(); self.error = error.localizedDescription }
    }
}
