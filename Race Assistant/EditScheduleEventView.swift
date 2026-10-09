import SwiftUI
import SwiftData

struct EditScheduleEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Role.name)
    private var allRoles: [Role]

    @Query(sort: \RaceClass.name)
    private var allRaceClasses: [RaceClass]

    let event: ScheduleEvent

    @State private var title: String
    @State private var plannedStart: Date
    @State private var plannedDuration: Int
    @State private var selectedConfiguration: CircuitConfiguration?
    @State private var isRace: Bool
    @State private var selectedRoles: [Role]
    @State private var selectedRaceClasses: [RaceClass]

    @State private var showingFinishConfirmation = false

    private var activeRoles: [Role] {
        allRoles.filter { $0.active }
    }

    private var activeRaceClasses: [RaceClass] {
        let allowed = event.stage?.availableClasses ?? []
        return allRaceClasses.filter { item in
            (item.active && allowed.contains { $0 === item }) || selectedRaceClasses.contains { $0 === item }
        }
    }

    private var minimumEventDate: Date {
        guard let stage = event.stage else {
            return plannedStart
        }

        return Calendar.current.startOfDay(
            for: stage.startDate
        )
    }

    private var maximumEventDate: Date {
        guard let stage = event.stage else {
            return plannedStart
        }

        let calendar = Calendar.current

        let endOfStageDay = calendar.startOfDay(
            for: stage.endDate
        )

        return calendar.date(
            byAdding: DateComponents(
                day: 1,
                second: -1
            ),
            to: endOfStageDay
        ) ?? stage.endDate
    }

    init(event: ScheduleEvent) {
        self.event = event
        _selectedConfiguration = State(initialValue: event.circuitConfiguration)

        _title = State(
            initialValue: event.title
        )

        _plannedStart = State(
            initialValue: event.plannedStart
        )

        _plannedDuration = State(
            initialValue: event.plannedDuration
        )
        
        _isRace = State(
            initialValue: event.isRace
        )

        _selectedRoles = State(
            initialValue: event.eventRoles
                .compactMap { $0.role }
        )

        _selectedRaceClasses = State(
            initialValue: event.eventClasses
                .compactMap { $0.raceClass }
        )

    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Статус

                if event.status == "finished" {
                    Section {
                        Label(
                            "Завершено",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)

                        if let actualDuration = event.actualDuration {
                            HStack {
                                Text("Фактическая длительность")

                                Spacer()

                                Text(
                                    durationText(actualDuration)
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // MARK: - Событие

                Section("Событие") {
                    TextField(
                        "Название",
                        text: $title
                    )

                    DatePicker(
                        "Дата и время",
                        selection: $plannedStart,
                        in: minimumEventDate...maximumEventDate,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                    
                    Toggle(
                        "Гонка",
                        isOn: $isRace
                    )
                    
                }

                if isRace, let circuit = event.stage?.circuit {
                    Section("Конфигурация гонки") {
                        ConfigurationPicker(circuit: circuit, selection: $selectedConfiguration,
                                            inherited: event.stage?.effectiveConfiguration, usesStageDefault: true)
                    }
                }

                // MARK: - Длительность

                Section("Длительность") {
                    Picker(
                        "Продолжительность",
                        selection: $plannedDuration
                    ) {
                        ForEach(
                            durationOptions,
                            id: \.self
                        ) { minutes in
                            Text(
                                durationText(minutes)
                            )
                            .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                // MARK: - Классы

                if !activeRaceClasses.isEmpty {
                Section("Классы соревнований") {
                    NavigationLink {
                        EditRaceClassSelectionView(
                            raceClasses: activeRaceClasses,
                            selectedRaceClasses: $selectedRaceClasses
                        )
                    } label: {
                        HStack {
                            Text("Классы")

                            Spacer()

                            Text(raceClassesSummary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                }
                // MARK: - Роли

                Section("Роли") {
                    NavigationLink {
                        EditRoleSelectionView(
                            roles: activeRoles,
                            selectedRoles: $selectedRoles
                        )
                    } label: {
                        HStack {
                            Text("Роли")

                            Spacer()

                            Text(rolesSummary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }


                // MARK: - Завершение

                if event.status != "finished" {
                    Section {
                        Button(
                            role: .destructive
                        ) {
                            showingFinishConfirmation = true
                        } label: {
                            HStack {
                                Spacer()

                                Label(
                                    "Завершить сейчас",
                                    systemImage: "checkmark.circle"
                                )

                                Spacer()
                            }
                        }
                    } footer: {
                        Text(
                            "Используй, если действие завершилось раньше запланированного времени."
                        )
                    }
                }
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
            .confirmationDialog(
                "Завершить событие?",
                isPresented: $showingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "Завершить сейчас",
                    role: .destructive
                ) {
                    finishNow()
                }

                Button(
                    "Отмена",
                    role: .cancel
                ) {}
            } message: {
                Text(
                    "Событие будет отмечено завершённым, а фактическая длительность зафиксируется на текущий момент."
                )
            }
        }
    }

    // MARK: - Duration

    private var durationOptions: [Int] {
        let shortDurations = Array(
            stride(
                from: 0,
                through: 60,
                by: 5
            )
        )

        let mediumDurations = Array(
            stride(
                from: 90,
                through: 240,
                by: 30
            )
        )

        let longDurations = [
            360,   // 6 ч
            480,   // 8 ч
            720,   // 12 ч
            1080,  // 18 ч
            1440   // 24 ч
        ]

        var options =
            shortDurations
            + mediumDurations
            + longDurations

        let existingDuration =
            event.plannedDuration

        if !options.contains(existingDuration) {
            options.append(existingDuration)
        }

        return options.sorted()
    }

    private func durationText(
        _ minutes: Int
    ) -> String {
        if minutes == 0 {
            return "Без длительности"
        }

        if minutes < 60 {
            return "\(minutes) мин"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours) ч"
        }

        return "\(hours) ч \(remainingMinutes) мин"
    }

    // MARK: - Summaries

    private var rolesSummary: String {
        if selectedRoles.isEmpty {
            return "Не выбраны"
        }

        return selectedRoles
            .map {
                $0.shortName.isEmpty
                    ? $0.name
                    : $0.shortName
            }
            .joined(separator: ", ")
    }

    private var raceClassesSummary: String {
        if selectedRaceClasses.isEmpty {
            return "Не выбраны"
        }

        return selectedRaceClasses
            .map {
                $0.shortName.isEmpty
                    ? $0.name
                    : $0.shortName
            }
            .joined(separator: ", ")
    }

    // MARK: - Save

    private func save() {
        event.title = title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        event.plannedStart = plannedStart
        event.plannedDuration = plannedDuration
        event.isRace = isRace
        event.circuitConfiguration = isRace ? selectedConfiguration : nil

        // Роли

        for eventRole in event.eventRoles {
            modelContext.delete(eventRole)
        }

        event.eventRoles.removeAll()

        for role in selectedRoles {
            let eventRole = EventRole(
                scheduleEvent: event,
                role: role
            )

            modelContext.insert(eventRole)
            event.eventRoles.append(eventRole)
        }

        // Классы

        for eventClass in event.eventClasses {
            modelContext.delete(eventClass)
        }

        event.eventClasses.removeAll()

        for raceClass in selectedRaceClasses {
            let eventClass = EventClass(
                scheduleEvent: event,
                raceClass: raceClass
            )

            modelContext.insert(eventClass)
            event.eventClasses.append(eventClass)
        }

        do {
            try modelContext.save()

            Task {
                if let stage = event.stage {
                    await NotificationManager.shared
                        .rescheduleNotifications(
                            for: stage
                        )

                    PhoneWatchConnectivityManager.shared
                        .send(
                            stage: stage
                        )
                }
            }

            dismiss()

        } catch {
            print(
                "Ошибка сохранения события: \(error)"
            )
        }
    }

    // MARK: - Finish

    private func finishNow() {
        let now = Date()

        let actualStart =
            event.actualStart
            ?? event.plannedStart

        let seconds =
            now.timeIntervalSince(
                actualStart
            )

        let minutes =
            max(
                0,
                Int(seconds / 60)
            )

        event.actualStart =
            actualStart

        event.actualDuration =
            minutes

        event.status =
            "finished"

        do {
            try modelContext.save()

            NotificationManager.shared
                .removeNotifications(
                    for: event
                )

            if let stage = event.stage {
                PhoneWatchConnectivityManager.shared
                    .send(
                        stage: stage
                    )
            }

            dismiss()

        } catch {
            print(
                "Ошибка завершения события: \(error)"
            )
        }
    }
}


// MARK: - Выбор ролей

private struct EditRoleSelectionView: View {
    let roles: [Role]

    @Binding
    var selectedRoles: [Role]

    var body: some View {
        List {
            ForEach(roles) { role in
                Button {
                    toggle(role)
                } label: {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(role.name)
                                .foregroundStyle(.primary)

                            if !role.shortName.isEmpty {
                                Text(role.shortName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if isSelected(role) {
                            Image(
                                systemName: "checkmark"
                            )
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Роли")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(
        _ role: Role
    ) -> Bool {
        selectedRoles.contains {
            $0 === role
        }
    }

    private func toggle(
        _ role: Role
    ) {
        if let index =
            selectedRoles.firstIndex(
                where: {
                    $0 === role
                }
            ) {

            selectedRoles.remove(
                at: index
            )

        } else {
            selectedRoles.append(role)
        }
    }
}


// MARK: - Выбор классов

private struct EditRaceClassSelectionView: View {
    let raceClasses: [RaceClass]

    @Binding
    var selectedRaceClasses: [RaceClass]

    var body: some View {
        List {
            ForEach(
                raceClasses
            ) { raceClass in

                Button {
                    toggle(raceClass)
                } label: {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(raceClass.name)
                                .foregroundStyle(.primary)

                            if !raceClass.shortName.isEmpty {
                                Text(raceClass.shortName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if isSelected(raceClass) {
                            Image(
                                systemName: "checkmark"
                            )
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .navigationTitle("Классы")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(
        _ raceClass: RaceClass
    ) -> Bool {
        selectedRaceClasses.contains {
            $0 === raceClass
        }
    }

    private func toggle(
        _ raceClass: RaceClass
    ) {
        if let index =
            selectedRaceClasses.firstIndex(
                where: {
                    $0 === raceClass
                }
            ) {

            selectedRaceClasses.remove(
                at: index
            )

        } else {
            selectedRaceClasses.append(
                raceClass
            )
        }
    }
}
