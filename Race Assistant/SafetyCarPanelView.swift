import SwiftUI
import SwiftData

struct SafetyCarPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let stage: Stage

    @State private var selectedEvent: ScheduleEvent?
    @State private var showingAddPeriod = false
    @State private var periodToEdit: SafetyCarPeriod?

    // MARK: - Events

    private var raceEvents: [ScheduleEvent] {
        stage.scheduleEvents
            .filter { $0.isRace }
            .sorted { $0.plannedStart < $1.plannedStart }
    }

    private var currentRaceEvent: ScheduleEvent? {
        let now = Date()

        return raceEvents.first { event in
            let start =
                event.actualStart
                ?? event.plannedStart

            let durationMinutes =
                event.actualDuration
                ?? event.plannedDuration

            let end =
                start.addingTimeInterval(
                    TimeInterval(
                        durationMinutes * 60
                    )
                )

            return now >= start && now < end
        }
    }

    // MARK: - Periods

    private var allSafetyCarPeriods: [SafetyCarPeriod] {
        raceEvents
            .flatMap { $0.safetyCarPeriods }
            .sorted {
                periodSortDate($0)
                    > periodSortDate($1)
            }
    }

    private var selectedRacePeriods: [SafetyCarPeriod] {
        guard let selectedEvent else {
            return []
        }

        return selectedEvent.safetyCarPeriods
            .sorted {
                periodSortDate($0)
                    > periodSortDate($1)
            }
    }

    private var activePeriod: SafetyCarPeriod? {
        allSafetyCarPeriods.first {
            $0.isActive
        }
    }

    // MARK: - Statistics

    private var selectedRaceLapCount: Int {
        selectedRacePeriods.reduce(0) {
            $0 + $1.lapCount
        }
    }

    private var stageLapCount: Int {
        allSafetyCarPeriods.reduce(0) {
            $0 + $1.lapCount
        }
    }

    var body: some View {
        NavigationStack {
            List {

                // MARK: Race selection

                Section("Заезд") {
                    Picker(
                        "Заезд",
                        selection: $selectedEvent
                    ) {
                        Text("Выберите заезд")
                            .tag(
                                nil as ScheduleEvent?
                            )

                        ForEach(raceEvents) { event in
                            Text(eventPickerTitle(event))
                                .tag(
                                    event as ScheduleEvent?
                                )
                        }
                    }

                    if let selectedEvent {
                        raceClassesView(
                            for: selectedEvent
                        )
                    }
                }

                // MARK: Live control

                Section {
                    if let activePeriod {
                        activePanel(activePeriod)
                    } else {
                        inactivePanel
                    }
                }

                // MARK: Selected race statistics

                if let selectedEvent {
                    Section(
                        "Статистика заезда"
                    ) {
                        LabeledContent(
                            "Заезд",
                            value:
                                eventSummary(
                                    selectedEvent
                                )
                        )

                        LabeledContent(
                            "Выездов Safety Car",
                            value:
                                "\(selectedRacePeriods.count)"
                        )

                        LabeledContent(
                            "Кругов под Safety Car",
                            value:
                                "\(selectedRaceLapCount)"
                        )
                    }
                }

                // MARK: Race history

                if !selectedRacePeriods.isEmpty {
                    Section(
                        "История заезда"
                    ) {
                        ForEach(
                            Array(
                                selectedRacePeriods
                                    .enumerated()
                            ),
                            id: \.element.persistentModelID
                        ) { index, period in

                            periodRow(
                                period,
                                number:
                                    selectedRacePeriods
                                        .count
                                    - index
                            )
                        }
                        .onDelete(
                            perform:
                                deleteSelectedRacePeriods
                        )
                    }
                }

                // MARK: Stage totals

                if !allSafetyCarPeriods.isEmpty {
                    Section(
                        "Итого за этап"
                    ) {
                        LabeledContent(
                            "Выездов Safety Car",
                            value:
                                "\(allSafetyCarPeriods.count)"
                        )

                        LabeledContent(
                            "Кругов под Safety Car",
                            value:
                                "\(stageLapCount)"
                        )
                    }
                }
            }
            .onAppear {
                if selectedEvent == nil {
                    selectedEvent =
                        currentRaceEvent
                        ?? raceEvents.first
                }
            }
            .navigationTitle(
                "Safety Car"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button {
                        showingAddPeriod = true
                    } label: {
                        Image(
                            systemName: "plus"
                        )
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .sheet(
                isPresented:
                    $showingAddPeriod
            ) {
                EditSafetyCarPeriodView(
                    stage: stage
                )
            }
            .sheet(
                item: $periodToEdit
            ) { period in
                EditSafetyCarPeriodView(
                    stage: stage,
                    period: period
                )
            }
        }
    }

    // MARK: - Active SC

    @ViewBuilder
    private func activePanel(
        _ period: SafetyCarPeriod
    ) -> some View {

        VStack(spacing: 16) {

            Image(
                systemName: "car.side.fill"
            )
            .font(
                .system(size: 44)
            )
            .foregroundStyle(.orange)

            Text(
                "SAFETY CAR АКТИВЕН"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            if let event =
                period.scheduleEvent {

                VStack(spacing: 4) {

                    Text(
                        "SC #\(periodNumber(period, in: event))"
                    )
                    .font(
                        .title3.bold()
                    )

                    Text(event.title)
                        .font(.subheadline)

                    raceClassesView(
                        for: event
                    )
                }
            }

            VStack(spacing: 2) {
                Text(
                    "КРУГОВ ПОД SC"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

                Text(
                    "\(period.lapCount)"
                )
                .font(
                    .system(
                        size: 64,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .contentTransition(
                    .numericText()
                )
            }

            HStack(spacing: 12) {

                Button {
                    removeLap(
                        from: period
                    )
                } label: {
                    Image(
                        systemName: "minus"
                    )
                    .font(
                        .title2.bold()
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 60)
                }
                .buttonStyle(
                    .bordered
                )
                .disabled(
                    period.lapCount == 0
                )

                Button {
                    addLap(
                        to: period
                    )
                } label: {
                    Label(
                        "+ КРУГ",
                        systemImage: "plus"
                    )
                    .font(
                        .title3.bold()
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                    .frame(height: 60)
                }
                .buttonStyle(
                    .borderedProminent
                )
            }

            Button(
                role: .destructive
            ) {
                finishSafetyCar(
                    period
                )
            } label: {
                Text(
                    "ЗАВЕРШИТЬ SC"
                )
                .fontWeight(
                    .semibold
                )
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 44)
            }
            .buttonStyle(.bordered)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(
            .vertical,
            12
        )
    }

    // MARK: - Inactive SC

    private var inactivePanel: some View {
        VStack(spacing: 16) {

            Image(
                systemName: "car.side"
            )
            .font(
                .system(size: 44)
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                "Safety Car не активен"
            )
            .font(.headline)

            if let selectedEvent {
                VStack(spacing: 4) {
                    Text(
                        selectedEvent.title
                    )
                    .fontWeight(
                        .semibold
                    )

                    raceClassesView(
                        for: selectedEvent
                    )
                }
            }

            Button {
                startSafetyCar()
            } label: {
                Text(
                    "НАЧАТЬ SC"
                )
                .font(
                    .title3.bold()
                )
                .frame(
                    maxWidth: .infinity
                )
                .frame(height: 60)
            }
            .buttonStyle(
                .borderedProminent
            )
            .disabled(
                selectedEvent == nil
                || activePeriod != nil
            )
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(
            .vertical,
            12
        )
    }

    // MARK: - History row

    @ViewBuilder
    private func periodRow(
        _ period: SafetyCarPeriod,
        number: Int
    ) -> some View {

        Button {
            periodToEdit = period
        } label: {

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                HStack {
                    Text(
                        "SC #\(number)"
                    )
                    .fontWeight(
                        .semibold
                    )

                    Spacer()

                    Text(
                        "\(period.lapCount) кр."
                    )
                    .fontWeight(
                        .semibold
                    )
                }

                if let startedAt =
                    period.startedAt {

                    HStack(spacing: 6) {

                        Text(
                            startedAt.formatted(
                                date: .omitted,
                                time: .shortened
                            )
                        )

                        if let endedAt =
                            period.endedAt {

                            Text("–")

                            Text(
                                endedAt.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                if !period.notes.isEmpty {
                    Text(period.notes)
                        .font(.caption)
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Race classes

    @ViewBuilder
    private func raceClassesView(
        for event: ScheduleEvent
    ) -> some View {

        let classes =
            event.eventClasses
                .compactMap {
                    $0.raceClass?.name
                }
                .joined(
                    separator: " · "
                )

        if !classes.isEmpty {
            Text(classes)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
        }
    }

    // MARK: - Helpers

    private func eventPickerTitle(
        _ event: ScheduleEvent
    ) -> String {
        let summary = eventSummary(event)

        if event === currentRaceEvent {
            return "● СЕЙЧАС · \(summary)"
        }

        return summary
    }

    private func eventSummary(
        _ event: ScheduleEvent
    ) -> String {
        let classes =
            event.eventClasses
                .compactMap {
                    $0.raceClass
                }
                .map {
                    $0.shortName.isEmpty
                        ? $0.name
                        : $0.shortName
                }
                .sorted()
                .joined(
                    separator: ", "
                )

        let time = displayTime(
            event.plannedStart
        )

        if classes.isEmpty {
            return time
        }

        return "\(classes) · \(time)"
    }

    private func displayTime(
        _ date: Date
    ) -> String {
        let seconds =
            Calendar.current.component(
                .second,
                from: date
            )

        let formatter = DateFormatter()
        formatter.locale =
            Locale(identifier: "ru_RU")
        formatter.dateFormat =
            seconds == 0
                ? "HH:mm"
                : "HH:mm:ss"

        return formatter.string(
            from: date
        )
    }

    private func periodSortDate(
        _ period: SafetyCarPeriod
    ) -> Date {

        period.startedAt
        ?? period.endedAt
        ?? period.scheduleEvent?
            .plannedStart
        ?? .distantPast
    }

    private func periodNumber(
        _ period: SafetyCarPeriod,
        in event: ScheduleEvent
    ) -> Int {

        let periods =
            event.safetyCarPeriods
                .sorted {
                    periodSortDate($0)
                        < periodSortDate($1)
                }

        guard let index =
            periods.firstIndex(
                where: {
                    $0 === period
                }
            )
        else {
            return 1
        }

        return index + 1
    }

    // MARK: - Actions

    private func startSafetyCar() {
        guard activePeriod == nil else {
            return
        }

        guard let selectedEvent else {
            return
        }

        let period =
            SafetyCarPeriod(
                startedAt: .now,
                lapCount: 0,
                notes: "",
                scheduleEvent:
                    selectedEvent
            )

        modelContext.insert(
            period
        )

        do {
            try modelContext.save()
        } catch {
            print(
                "Ошибка запуска SC: \(error)"
            )
        }
    }

    private func addLap(
        to period: SafetyCarPeriod
    ) {
        period.lapCount += 1

        saveContext(
            errorMessage:
                "Ошибка сохранения круга SC"
        )
    }

    private func removeLap(
        from period: SafetyCarPeriod
    ) {
        guard period.lapCount > 0 else {
            return
        }

        period.lapCount -= 1

        saveContext(
            errorMessage:
                "Ошибка сохранения круга SC"
        )
    }

    private func finishSafetyCar(
        _ period: SafetyCarPeriod
    ) {
        period.endedAt = .now

        do {
            try modelContext.save()

            periodToEdit =
                period

        } catch {
            print(
                "Ошибка завершения SC: \(error)"
            )
        }
    }

    private func deleteSelectedRacePeriods(
        at offsets: IndexSet
    ) {
        for index in offsets {
            modelContext.delete(
                selectedRacePeriods[index]
            )
        }

        saveContext(
            errorMessage:
                "Ошибка удаления SC"
        )
    }

    private func saveContext(
        errorMessage: String
    ) {
        do {
            try modelContext.save()
        } catch {
            print(
                "\(errorMessage): \(error)"
            )
        }
    }
}
