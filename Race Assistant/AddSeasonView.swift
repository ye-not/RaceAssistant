import SwiftUI
import SwiftData

struct AddSeasonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let championship: Championship

    @State private var year = Calendar.current.component(.year, from: Date())

    var body: some View {
        NavigationStack {
            Form {
                Section("Сезон") {
                    Picker("Год", selection: $year) {
                        ForEach(2000...2100, id: \.self) { value in
                            Text(String(value))
                                .tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                }
            }
            .navigationTitle("Новый сезон")
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
                }
            }
        }
    }

    private func save() {
        let season = Season(
            year: year,
            championship: championship
        )

        modelContext.insert(season)
        championship.seasons.append(season)

        dismiss()
    }
}
