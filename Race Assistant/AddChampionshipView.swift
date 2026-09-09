import SwiftUI
import SwiftData

struct AddChampionshipView: View {
    let onCreated: (Championship) -> Void

    init(onCreated: @escaping (Championship) -> Void = { _ in }) {
        self.onCreated = onCreated
    }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var organizer = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Чемпионат") {
                    TextField("Название", text: $name)
                    TextField("Организатор", text: $organizer)
                }
            }
            .navigationTitle("Новый чемпионат")
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
                        name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }
        }
    }

    private func save() {
        let championship = Championship(
            name: name.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            organizer: organizer.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )

        modelContext.insert(championship)

        do {
            try modelContext.save()
            dismiss()
            onCreated(championship)
        } catch {
            print("Ошибка сохранения чемпионата: \(error)")
        }
    }
}
