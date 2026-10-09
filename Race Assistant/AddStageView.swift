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
    @State private var selectedConfiguration: CircuitConfiguration?

    @Query(sort: \Role.name) private var roles: [Role]
    @State private var participation: StageParticipation = .unspecified
    @State private var officialRole: Role?
    @State private var selectedClasses: [RaceClass] = []

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

                if let circuit = selectedCircuit {
                    Section("Конфигурация") {
                        ConfigurationPicker(circuit: circuit, selection: $selectedConfiguration)
                    }
                }

                Section("Моё участие") {
                    Picker("Участие на этапе", selection: $participation) {
                        ForEach(StageParticipation.allCases, id: \.self) { value in Text(value.title).tag(value) }
                    }
                    if participation == .official {
                        Picker("Служебная роль", selection: $officialRole) {
                            Text("Не выбрана").tag(nil as Role?)
                            ForEach(roles.filter { $0.active || $0 === officialRole }) { role in
                                Text(role.shortName.isEmpty ? role.name : "\(role.name) (\(role.shortName))").tag(role as Role?)
                            }
                        }
                    }
                    if participation == .athlete {
                        ForEach(season.championship?.raceClasses ?? []) { value in
                            Toggle(value.shortName.isEmpty ? value.name : value.shortName, isOn: Binding(
                                get: { selectedClasses.contains { $0 === value } },
                                set: { selected in
                                    if selected { selectedClasses.append(value) }
                                    else { selectedClasses.removeAll { $0 === value } }
                                }
                            ))
                        }
                        Text("Классы также можно выбрать на экране этапа после загрузки расписания.").font(.caption).foregroundStyle(.secondary)
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
            .onChange(of: selectedCircuit?.persistentModelID) { _, _ in
                selectedConfiguration = nil
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

        stage.circuitConfiguration = selectedConfiguration
        stage.participation = participation
        stage.myRole = participation == .official ? officialRole : nil
        stage.participationClasses = selectedClasses
        stage.raceClasses = season.championship?.raceClasses.filter { $0.active } ?? []
        stage.classesConfigured = true
        modelContext.insert(stage)
        season.stages.append(stage)

        do {
            try modelContext.save()
            dismiss()
            PhoneWatchConnectivityManager.shared.sendPreferredStage()
            onCreated(stage)
        } catch {
            print("Ошибка сохранения этапа: \(error)")
        }
    }
}
