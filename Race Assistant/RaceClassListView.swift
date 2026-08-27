import SwiftUI
import SwiftData

struct RaceClassListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \RaceClass.name)
    private var raceClasses: [RaceClass]

    @State private var showingAddRaceClass = false

    var body: some View {
        List {
            if raceClasses.isEmpty {
                ContentUnavailableView(
                    "Нет классов",
                    systemImage: "car.2",
                    description: Text("Добавь первый класс соревнований")
                )
            } else {
                ForEach(raceClasses) { raceClass in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(raceClass.name)
                                .font(.headline)

                            if !raceClass.shortName.isEmpty {
                                Text(raceClass.shortName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { raceClass.active },
                                set: { newValue in
                                    raceClass.active = newValue
                                    saveChanges()
                                }
                            )
                        )
                        .labelsHidden()
                    }
                }
            }
        }
        .navigationTitle("Классы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRaceClass = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRaceClass) {
            AddRaceClassView()
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Ошибка сохранения классов: \(error)")
        }
    }
}
