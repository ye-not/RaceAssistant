import SwiftUI
import SwiftData

struct AddStageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Circuit.name)
    private var circuits: [Circuit]

    let season: Season
    let onCreated: (Stage) -> Void

    init(
        season: Season,
        onCreated: @escaping (Stage) -> Void = { _ in }
    ) {
        self.season = season
        self.onCreated = onCreated
    }

    @State private var name = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var selectedCircuit: Circuit?

    var body: some View {
        NavigationStack {
            Form {
                Section("Этап") {
                    TextField("Название", text: $name)

                    Picker("Автодром", selection: $selectedCircuit) {
                        Text("Не выбран")
                            .tag(nil as Circuit?)

                        ForEach(circuits) { circuit in
                            Text(circuit.name)
                                .tag(circuit as Circuit?)
                        }
                    }
                }

                Section("Даты") {
                    DatePicker(
                        "Начало",
                        selection: $startDate,
                        displayedComponents: .date
                    )

                    DatePicker(
                        "Окончание",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: .date
                    )
                }
            }
            .navigationTitle("Новый этап")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedCircuit == nil
                    )
                }
            }
            .onChange(of: startDate) { _, newValue in
                if endDate < newValue {
                    endDate = newValue
                }
            }
        }
    }

    private func save() {
        let stage = Stage(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: startDate,
            endDate: endDate,
            season: season,
            circuit: selectedCircuit
        )

        modelContext.insert(stage)
        season.stages.append(stage)

        do {
            try modelContext.save()
            dismiss()
            onCreated(stage)
        } catch {
            print("Ошибка сохранения этапа: \(error)")
        }
    }
}
