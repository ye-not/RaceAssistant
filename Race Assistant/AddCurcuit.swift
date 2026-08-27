import SwiftUI
import SwiftData

struct AddCircuitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var city = ""
    @State private var country = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Автодром") {
                    TextField("Название", text: $name)
                    TextField("Город", text: $city)
                    TextField("Страна", text: $country)
                }
            }
            .navigationTitle("Новый автодром")
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
        let circuit = Circuit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            country: country.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        modelContext.insert(circuit)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Ошибка сохранения автодрома: \(error)")
        }
    }
}
