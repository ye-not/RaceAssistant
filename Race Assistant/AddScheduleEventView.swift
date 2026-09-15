import SwiftUI
import SwiftData

struct AddScheduleEventView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Role.name)
    private var allRoles: [Role]

    @Query(sort: \RaceClass.name)
    private var allRaceClasses: [RaceClass]

    let stage: Stage

    @State private var title = ""
    @State private var plannedStart: Date
    @State private var plannedDuration = 30
    @State private var isRace = false

    @State private var selectedRoles: [Role] = []
    @State private var selectedRaceClasses: [RaceClass] = []

    private var activeRoles: [Role] {
        allRoles.filter { $0.active }
    }

    private var activeRaceClasses: [RaceClass] {
        let allowed = stage.season?.championship?.raceClasses ?? []
        return allRaceClasses.filter { item in
            (item.active && allowed.contains { $0 === item }) || selectedRaceClasses.contains { $0 === item }
        }
    }

    private var minimumEventDate: Date {
        Calendar.current.startOfDay(
            for: stage.startDate
        )
    }

    private var maximumEventDate: Date {
        let calendar = Calendar.current

        let endOfStageDay =
            calendar.startOfDay(
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

    init(stage: Stage) {
        self.stage = stage

        let calendar = Calendar.current

        let startOfStageDay =
            calendar.startOfDay(
                for: stage.startDate
            )

        _plannedStart = State(
            initialValue: startOfStageDay
        )
    }

    var body: some View {
        NavigationStack {
            Form {

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
                        RaceClassSelectionView(
                            raceClasses: activeRaceClasses,
                            selectedRaceClasses:
                                $selectedRaceClasses
                        )
                    } label: {
                        HStack {
                            Text("Классы")

                            Spacer()

                            Text(
                                raceClassesSummary
                            )
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                        }
                    }
                }

                }
                // MARK: - Роли

                Section("Роли") {
                    NavigationLink {
                        RoleSelectionView(
                            roles: activeRoles,
                            selectedRoles:
                                $selectedRoles
                        )
                    } label: {
                        HStack {
                            Text("Роли")

                            Spacer()

                            Text(
                                rolesSummary
                            )
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                        }
                    }
                }

    
            }
            .navigationTitle(
                "Новое событие"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
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

        return shortDurations
            + mediumDurations
            + longDurations
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

        let hours =
            minutes / 60

        let remainingMinutes =
            minutes % 60

        if remainingMinutes == 0 {
            return "\(hours) ч"
        }

        return
            "\(hours) ч \(remainingMinutes) мин"
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
        let event =
            ScheduleEvent(
                title:
                    title
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                plannedStart:
                    plannedStart,
                plannedDuration:
                    plannedDuration,
                stage:
                    stage
            )
        
        event.isRace = isRace

        modelContext.insert(event)

        // Роли

        for role in selectedRoles {
            let eventRole =
                EventRole(
                    scheduleEvent:
                        event,
                    role:
                        role
                )

            modelContext.insert(
                eventRole
            )

            event.eventRoles.append(
                eventRole
            )
        }

        // Классы

        for raceClass in selectedRaceClasses {
            let eventClass =
                EventClass(
                    scheduleEvent:
                        event,
                    raceClass:
                        raceClass
                )

            modelContext.insert(
                eventClass
            )

            event.eventClasses.append(
                eventClass
            )
        }

        stage.scheduleEvents.append(
            event
        )

        do {
            try modelContext.save()

            Task {
                await NotificationManager.shared
                    .rescheduleNotifications(
                        for: stage
                    )

                PhoneWatchConnectivityManager.shared
                    .send(
                        stage: stage
                    )
            }

            dismiss()

        } catch {
            print(
                "Ошибка сохранения события: \(error)"
            )
        }
    }
}


// MARK: - Выбор ролей

private struct RoleSelectionView: View {
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
                                .foregroundStyle(
                                    .primary
                                )

                            if !role.shortName.isEmpty {
                                Text(
                                    role.shortName
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        Spacer()

                        if isSelected(role) {
                            Image(
                                systemName:
                                    "checkmark"
                            )
                            .fontWeight(
                                .semibold
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Роли")
        .navigationBarTitleDisplayMode(
            .inline
        )
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

            selectedRoles.append(
                role
            )
        }
    }
}


// MARK: - Выбор классов

private struct RaceClassSelectionView: View {
    let raceClasses: [RaceClass]

    @Binding
    var selectedRaceClasses: [RaceClass]

    var body: some View {
        List {
            ForEach(
                raceClasses
            ) { raceClass in

                Button {
                    toggle(
                        raceClass
                    )
                } label: {

                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: 3
                        ) {
                            Text(
                                raceClass.name
                            )
                            .foregroundStyle(
                                .primary
                            )

                            if !raceClass
                                .shortName
                                .isEmpty {

                                Text(
                                    raceClass
                                        .shortName
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        Spacer()

                        if isSelected(
                            raceClass
                        ) {
                            Image(
                                systemName:
                                    "checkmark"
                            )
                            .fontWeight(
                                .semibold
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Классы")
        .navigationBarTitleDisplayMode(
            .inline
        )
    }

    private func isSelected(
        _ raceClass: RaceClass
    ) -> Bool {
        selectedRaceClasses
            .contains {
                $0 === raceClass
            }
    }

    private func toggle(
        _ raceClass: RaceClass
    ) {
        if let index =
            selectedRaceClasses
                .firstIndex(
                    where: {
                        $0 === raceClass
                    }
                ) {

            selectedRaceClasses
                .remove(
                    at: index
                )

        } else {

            selectedRaceClasses
                .append(
                    raceClass
                )
        }
    }
}
