import SwiftUI
import SwiftData

struct AddSeasonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let championship: Championship
    let onCreated: (Season) -> Void

    @State private var name = ""
    @State private var hasDeclaredYears = true
    @State private var declaredStartYear =
        Calendar.current.component(.year, from: Date())
    @State private var declaredEndYear =
        Calendar.current.component(.year, from: Date())

    init(
        championship: Championship,
        onCreated: @escaping (Season) -> Void = { _ in }
    ) {
        self.championship = championship
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Сезон") {
                    TextField(
                        "Название, например 2026 или 2026/27",
                        text: $name
                    )
                }

                Section {
                    Toggle(
                        "Указать годы проведения",
                        isOn: $hasDeclaredYears
                    )

                    if hasDeclaredYears {
                        Picker("Начало", selection: $declaredStartYear) {
                            ForEach(2000...2100, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }

                        Picker("Окончание", selection: $declaredEndYear) {
                            ForEach(2000...2100, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    }
                } header: {
                    Text("Годы проведения")
                } footer: {
                    Text("Годы необязательны. Фактический период сезона определяется датами добавленных этапов.")
                }
            }
            .navigationTitle("Новый сезон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .onChange(of: declaredStartYear) {
                if declaredEndYear < declaredStartYear {
                    declaredEndYear = declaredStartYear
                }
            }
        }
    }

    private func save() {
        let trimmedName =
            name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }

        let season = Season(
            name: trimmedName,
            declaredStartYear: hasDeclaredYears ? declaredStartYear : nil,
            declaredEndYear: hasDeclaredYears ? declaredEndYear : nil,
            championship: championship
        )

        modelContext.insert(season)
        championship.seasons.append(season)

        do {
            try modelContext.save()
            dismiss()
            onCreated(season)
        } catch {
            print("Ошибка сохранения сезона: \(error)")
        }
    }
}
