import SwiftUI
import SwiftData

struct AddRaceClassView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortName = ""
    @State private var active = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Класс") {
                    TextField("Название", text: $name)
                    TextField("Сокращение", text: $shortName)
                }

                Section {
                    Toggle("Активен", isOn: $active)
                }
            }
            .navigationTitle("Новый класс")
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
                    )
                }
            }
        }
    }

    private func save() {
        let raceClass = RaceClass(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            shortName: shortName.trimmingCharacters(in: .whitespacesAndNewlines),
            active: active
        )

        modelContext.insert(raceClass)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Ошибка сохранения класса: \(error)")
        }
    }
}
