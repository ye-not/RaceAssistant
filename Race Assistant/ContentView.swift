import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Championship.name)
    private var championships: [Championship]

    @Query
    private var stages: [Stage]

    @State private var showingAddChampionship = false
    @State private var eventToEdit: ScheduleEvent?

    var body: some View {
        NavigationStack {
            TimelineView(
                .periodic(
                    from: .now,
                    by: 60
                )
            ) { context in
                mainContent(
                    now: context.date
                )
            }
            .navigationTitle("Race Assistant")
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button {
                        showingAddChampionship = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(
                isPresented: $showingAddChampionship
            ) {
                AddChampionshipView()
            }
            .sheet(
                item: $eventToEdit
            ) { event in
                EditScheduleEventView(
                    event: event
                )
            }
            .task {
                await NotificationManager.shared
                    .requestPermission()
            }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(
        now: Date
    ) -> some View {
        VStack(spacing: 0) {
            List {

                // MARK: - Сегодня

                if let stage = currentStage(
                    now: now
                ) {
                    Section {

                        // MARK: Информация об этапе

                        NavigationLink {
                            StageDetailView(
                                stage: stage
                            )
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 5
                            ) {

                                // Чемпионат + сезон

                                if let season = stage.season {
                                    HStack(spacing: 5) {
                                        if let championship =
                                            season.championship {

                                            Text(
                                                championship.name
                                            )
                                        }

                                        Text("·")

                                        Text(
                                            String(
                                                season.year
                                            )
                                        )
                                    }
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                // Этап

                                Text(stage.name)
                                    .font(.headline)

                                // Автодром

                                if let circuit =
                                    stage.circuit {

                                    Label(
                                        circuit.name,
                                        systemImage:
                                            "road.lanes"
                                    )
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }

                                // Моя роль

                                if let role =
                                    stage.myRole {

                                    Label(
                                        "Моя роль: \(role.shortName.isEmpty ? role.name : role.shortName)",
                                        systemImage:
                                            "person.fill"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )

                                } else {

                                    Label(
                                        "Роль не выбрана",
                                        systemImage:
                                            "person"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(
                                        .secondary
                                    )
                                }
                            }
                            .padding(
                                .vertical,
                                2
                            )
                        }

                        // MARK: Расписание

                        let events =
                            todayEvents(
                                stage: stage,
                                now: now
                            )

                        if events.isEmpty {

                            Text(
                                stage.myRole == nil
                                    ? "На сегодня событий нет"
                                    : "Для выбранной роли событий на сегодня нет"
                            )
                            .foregroundStyle(
                                .secondary
                            )

                        } else {

                            let visible =
                                visibleEvents(
                                    events: events,
                                    now: now
                                )

                            let current =
                                currentEvent(
                                    events: events,
                                    now: now
                                )

                            let next =
                                nextEvent(
                                    events: events,
                                    now: now
                                )

                            ForEach(visible) { event in

                                let eventIsCurrent =
                                    event === current

                                let eventIsNext =
                                    event === next

                                if eventIsCurrent {

                                    // Текущее событие можно открыть
                                    // прямо с главного экрана.

                                    Button {
                                        eventToEdit =
                                            event
                                    } label: {
                                        eventRow(
                                            event,
                                            now: now,
                                            isCurrent: true,
                                            isNext: false
                                        )
                                    }
                                    .buttonStyle(.plain)

                                } else {

                                    eventRow(
                                        event,
                                        now: now,
                                        isCurrent: false,
                                        isNext:
                                            eventIsNext
                                    )
                                }
                            }

                            if visible.count <
                                events.count {

                                NavigationLink {
                                    StageDetailView(
                                        stage: stage
                                    )
                                } label: {
                                    HStack {
                                        Spacer()

                                        Text(
                                            "Показать всё расписание"
                                        )
                                        .font(.footnote)
                                        .foregroundStyle(
                                            .secondary
                                        )

                                        Spacer()
                                    }
                                }
                            }
                        }

                    } header: {
                        Text("Сегодня")
                    }
                }

                // MARK: - Предстоящие этапы

                Section("Предстоящие этапы") {

                    let upcoming =
                        upcomingStages(
                            now: now
                        )

                    if upcoming.isEmpty {

                        Text(
                            "Предстоящих этапов нет"
                        )
                        .foregroundStyle(
                            .secondary
                        )

                    } else {

                        ForEach(upcoming) { stage in
                            NavigationLink {
                                StageDetailView(
                                    stage: stage
                                )
                            } label: {
                                upcomingStageRow(
                                    stage
                                )
                            }
                        }
                    }
                }

                // MARK: - Чемпионаты

                Section {
                    ForEach(
                        championships
                    ) { championship in

                        NavigationLink {
                            ChampionshipDetailView(
                                championship:
                                    championship
                            )
                        } label: {
                            Text(
                                championship.name
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                    .onDelete(
                        perform:
                            deleteChampionships
                    )

                } header: {
                    Text("Управление")
                }
            }

            // MARK: - Справочники

            NavigationLink {
                ReferenceDataView()
            } label: {
                Text(
                    "Редактировать справочники"
                )
                .font(.footnote)
                .foregroundStyle(
                    .secondary
                )
                .padding(
                    .vertical,
                    12
                )
            }
        }
    }

    // MARK: - Current Stage

    private func currentStage(
        now: Date
    ) -> Stage? {
        let calendar =
            Calendar.current

        let today =
            calendar.startOfDay(
                for: now
            )

        return stages.first { stage in

            let start =
                calendar.startOfDay(
                    for: stage.startDate
                )

            let end =
                calendar.startOfDay(
                    for: stage.endDate
                )

            return
                today >= start &&
                today <= end
        }
    }

    // MARK: - Upcoming Stages

    private func upcomingStages(
        now: Date
    ) -> [Stage] {
        let calendar =
            Calendar.current

        let today =
            calendar.startOfDay(
                for: now
            )

        return stages
            .filter { stage in
                let start =
                    calendar.startOfDay(
                        for: stage.startDate
                    )

                return start > today
            }
            .sorted {
                $0.startDate <
                $1.startDate
            }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private func upcomingStageRow(
        _ stage: Stage
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            // Серия

            if let championship =
                stage.season?
                    .championship {

                Text(
                    championship.name
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    .secondary
                )
            }

            // Даты

            Text(
                stageDateText(stage)
            )
            .font(.subheadline)
            .fontWeight(.semibold)

            // Название этапа

            Text(stage.name)
                .font(.headline)

            // Автодром

            if let circuit =
                stage.circuit {

                Label(
                    circuit.name,
                    systemImage:
                        "road.lanes"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .padding(
            .vertical,
            3
        )
    }

    private func stageDateText(
        _ stage: Stage
    ) -> String {
        let calendar =
            Calendar.current

        if calendar.isDate(
            stage.startDate,
            inSameDayAs: stage.endDate
        ) {
            return stage.startDate.formatted(
                .dateTime
                    .day()
                    .month(.abbreviated)
            )
        }

        let sameMonth =
            calendar.component(
                .month,
                from: stage.startDate
            )
            ==
            calendar.component(
                .month,
                from: stage.endDate
            )

        if sameMonth {

            let startDay =
                stage.startDate.formatted(
                    .dateTime
                        .day()
                )

            let endDate =
                stage.endDate.formatted(
                    .dateTime
                        .day()
                        .month(.abbreviated)
                )

            return
                "\(startDay)–\(endDate)"
        }

        let start =
            stage.startDate.formatted(
                .dateTime
                    .day()
                    .month(.abbreviated)
            )

        let end =
            stage.endDate.formatted(
                .dateTime
                    .day()
                    .month(.abbreviated)
            )

        return
            "\(start) – \(end)"
    }

    // MARK: - Today Events

    private func todayEvents(
        stage: Stage,
        now: Date
    ) -> [ScheduleEvent] {
        let calendar =
            Calendar.current

        let events =
            stage.scheduleEvents
                .filter {
                    calendar.isDate(
                        $0.plannedStart,
                        inSameDayAs: now
                    )
                }
                .sorted {
                    $0.plannedStart <
                    $1.plannedStart
                }

        guard let myRole =
            stage.myRole
        else {
            return events
        }

        return events.filter { event in

            if event.eventRoles.isEmpty {
                return true
            }

            return event.eventRoles
                .contains { eventRole in
                    eventRole.role
                        === myRole
                }
        }
    }

    // MARK: - Event State

    private func eventEnd(
        _ event: ScheduleEvent
    ) -> Date {
        Calendar.current.date(
            byAdding: .minute,
            value: event.plannedDuration,
            to: event.plannedStart
        ) ?? event.plannedStart
    }

    private func isFinished(
        _ event: ScheduleEvent
    ) -> Bool {
        event.status == "finished"
    }

    private func isCurrent(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {

        // Ручное завершение имеет приоритет
        // над расчётной длительностью.

        guard !isFinished(event)
        else {
            return false
        }

        guard event.plannedDuration > 0
        else {
            return false
        }

        return
            now >= event.plannedStart &&
            now < eventEnd(event)
    }

    private func isPast(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {

        // Завершённое вручную событие
        // сразу считается прошедшим.

        if isFinished(event) {
            return true
        }

        if event.plannedDuration == 0 {
            return
                now >= event.plannedStart
        }

        return
            now >= eventEnd(event)
    }

    private func currentEvent(
        events: [ScheduleEvent],
        now: Date
    ) -> ScheduleEvent? {
        events.first {
            isCurrent(
                $0,
                now: now
            )
        }
    }

    private func nextEvent(
        events: [ScheduleEvent],
        now: Date
    ) -> ScheduleEvent? {
        events.first {
            !isFinished($0) &&
            $0.plannedStart > now
        }
    }

    // MARK: - Visible Events

    private func visibleEvents(
        events: [ScheduleEvent],
        now: Date
    ) -> [ScheduleEvent] {

        let past =
            events
                .filter {
                    isPast(
                        $0,
                        now: now
                    )
                }
                .suffix(2)

        let current =
            events
                .filter {
                    isCurrent(
                        $0,
                        now: now
                    )
                }

        let future =
            events
                .filter {
                    !isFinished($0) &&
                    $0.plannedStart > now
                }
                .prefix(5)

        var result:
            [ScheduleEvent] = []

        result.append(
            contentsOf: past
        )

        result.append(
            contentsOf: current
        )

        result.append(
            contentsOf: future
        )

        return result
    }

    // MARK: - Event Row

    @ViewBuilder
    private func eventRow(
        _ event: ScheduleEvent,
        now: Date,
        isCurrent: Bool,
        isNext: Bool
    ) -> some View {

        let past =
            isPast(
                event,
                now: now
            )

        HStack(
            alignment: .top,
            spacing: 14
        ) {

            // Время

            Text(
                event.plannedStart
                    .formatted(
                        date: .omitted,
                        time: .shortened
                    )
            )
            .font(
                past
                    ? .subheadline
                    : .headline
            )
            .monospacedDigit()
            .strikethrough(past)
            .foregroundStyle(
                past
                    ? .tertiary
                    : .primary
            )
            .frame(
                width: 58,
                alignment: .leading
            )

            VStack(
                alignment: .leading,
                spacing:
                    past ? 2 : 4
            ) {

                // Текущее событие

                if isCurrent {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(
                                width: 7,
                                height: 7
                            )

                        Text("СЕЙЧАС")
                            .font(.caption2)
                            .fontWeight(
                                .semibold
                            )

                        Text("·")

                        Text(
                            timeRemainingText(
                                event: event,
                                now: now
                            )
                        )
                        .font(.caption2)
                    }
                    .foregroundStyle(
                        .green
                    )
                }

                // Следующее событие

                if isNext {
                    HStack(spacing: 6) {
                        Text(
                            "СЛЕДУЮЩЕЕ"
                        )
                        .font(.caption2)
                        .fontWeight(
                            .semibold
                        )

                        Text("·")

                        Text(
                            timeUntilText(
                                event: event,
                                now: now
                            )
                        )
                        .font(.caption2)
                    }
                    .foregroundStyle(
                        .secondary
                    )
                }

                // Завершено досрочно

                if isFinished(event) {
                    Label(
                        "Завершено",
                        systemImage:
                            "checkmark.circle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        .tertiary
                    )
                }

                // Название

                Text(event.title)
                    .font(
                        past
                            ? .subheadline
                            : .headline
                    )
                    .fontWeight(
                        isCurrent || isNext
                            ? .semibold
                            : .regular
                    )
                    .strikethrough(past)
                    .foregroundStyle(
                        past
                            ? .tertiary
                            : .primary
                    )

                // Классы

                if !classesText(
                    for: event
                ).isEmpty {

                    Text(
                        classesText(
                            for: event
                        )
                    )
                    .font(.caption)
                    .strikethrough(past)
                    .foregroundStyle(
                        past
                            ? .tertiary
                            : .secondary
                    )
                }

                // Роли

                if !rolesText(
                    for: event
                ).isEmpty {

                    Text(
                        rolesText(
                            for: event
                        )
                    )
                    .font(.caption)
                    .strikethrough(past)
                    .foregroundStyle(
                        past
                            ? .tertiary
                            : .secondary
                    )
                }
            }
        }
        .padding(
            .vertical,
            isCurrent || isNext
                ? 5
                : (past ? 0 : 2)
        )
        .opacity(
            past ? 0.55 : 1.0
        )
    }

    // MARK: - Time

    private func timeUntilText(
        event: ScheduleEvent,
        now: Date
    ) -> String {

        let seconds =
            event.plannedStart
                .timeIntervalSince(now)

        let minutes =
            max(
                0,
                Int(
                    ceil(
                        seconds / 60
                    )
                )
            )

        if minutes == 0 {
            return "сейчас"
        }

        if minutes < 60 {
            return
                "через \(minutes) мин"
        }

        let hours =
            minutes / 60

        let remainingMinutes =
            minutes % 60

        if remainingMinutes == 0 {
            return
                "через \(hours) ч"
        }

        return
            "через \(hours) ч \(remainingMinutes) мин"
    }

    private func timeRemainingText(
        event: ScheduleEvent,
        now: Date
    ) -> String {

        let end =
            eventEnd(event)

        let seconds =
            end.timeIntervalSince(now)

        let minutes =
            max(
                0,
                Int(
                    ceil(
                        seconds / 60
                    )
                )
            )

        if minutes == 0 {
            return
                "заканчивается сейчас"
        }

        if minutes < 60 {
            return
                "осталось \(minutes) мин"
        }

        let hours =
            minutes / 60

        let remainingMinutes =
            minutes % 60

        if remainingMinutes == 0 {
            return
                "осталось \(hours) ч"
        }

        return
            "осталось \(hours) ч \(remainingMinutes) мин"
    }

    // MARK: - Classes

    private func classesText(
        for event: ScheduleEvent
    ) -> String {

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
                separator: " · "
            )
    }

    // MARK: - Roles

    private func rolesText(
        for event: ScheduleEvent
    ) -> String {

        event.eventRoles
            .compactMap {
                $0.role
            }
            .map {
                $0.shortName.isEmpty
                    ? $0.name
                    : $0.shortName
            }
            .sorted()
            .joined(
                separator: " · "
            )
    }

    // MARK: - Delete Championship

    private func deleteChampionships(
        offsets: IndexSet
    ) {
        for index in offsets {
            modelContext.delete(
                championships[index]
            )
        }

        do {
            try modelContext.save()

        } catch {
            print(
                "Ошибка удаления чемпионата: \(error)"
            )
        }
    }
}
