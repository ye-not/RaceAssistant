import SwiftUI
import SwiftData

struct EditStageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Circuit.name)
    private var circuits: [Circuit]

    let stage: Stage

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedCircuit: Circuit?
    @State private var selectedConfiguration: CircuitConfiguration?

    init(stage: Stage) {
        self.stage = stage

        _name = State(initialValue: stage.name)
        _startDate = State(initialValue: stage.startDate)
        _endDate = State(initialValue: stage.endDate)
        _selectedCircuit = State(initialValue: stage.circuit)
        _selectedConfiguration = State(initialValue: stage.circuitConfiguration)
        _participation = State(initialValue: stage.participation)
        _officialRole = State(initialValue: stage.myRole)
        _selectedClasses = State(initialValue: stage.participationClasses)
    }

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
                        ForEach(stage.season?.championship?.raceClasses ?? []) { value in
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
            .navigationTitle("Редактировать этап")
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
        stage.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        stage.startDate = startDate
        stage.endDate = endDate
        if stage.circuit !== selectedCircuit {
            for event in stage.scheduleEvents { event.circuitConfiguration = nil }
        }
        stage.circuit = selectedCircuit
        stage.circuitConfiguration = selectedConfiguration
        stage.participation = participation
        stage.myRole = participation == .official ? officialRole : nil
        stage.participationClasses = selectedClasses

        do {
            try modelContext.save()
            PhoneWatchConnectivityManager.shared.send(stage: stage)
            dismiss()
        } catch {
            print("Ошибка сохранения этапа: \(error)")
        }
    }
}
