import SwiftUI
import SwiftData

struct AddRoleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var shortName = ""
    @State private var active = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Роль") {
                    TextField("Название", text: $name)
                    TextField("Сокращение", text: $shortName)
                }

                Section {
                    Toggle("Активна", isOn: $active)
                }
            }
            .navigationTitle("Новая роль")
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
        let role = Role(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            shortName: shortName.trimmingCharacters(in: .whitespacesAndNewlines),
            active: active
        )

        modelContext.insert(role)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Ошибка сохранения роли: \(error)")
        }
    }
}
