import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Championship.name)
    private var championships: [Championship]

    @Query
    private var stages: [Stage]

    @ScaledMetric(relativeTo: .headline) private var timeColumnWidth: CGFloat = 82

    @StateObject private var stewardRouter = StewardNotificationRouter.shared
    @State private var showingAddChampionship = false
    @State private var showingStagePicker = false
    @State private var showingSchedulePicker = false
    @State private var eventToEdit: ScheduleEvent?
    @State private var championshipToOpen: Championship?

    var body: some View {
        NavigationStack {
            TimelineView(
                .periodic(
                    from: .now,
                    by: 1
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
                    Menu {
                        Button("Новый чемпионат", systemImage: "flag") {
                            showingAddChampionship = true
                        }
                        Button("Новый этап", systemImage: "calendar.badge.plus") {
                            showingStagePicker = true
                        }
                        Button("Загрузить расписание", systemImage: "doc.badge.arrow.up") {
                            showingSchedulePicker = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(
                isPresented: $showingAddChampionship
            ) {
                AddChampionshipView { championshipToOpen = $0 }
            }
            .navigationDestination(item: $championshipToOpen) { ChampionshipDetailView(championship: $0) }
            .sheet(isPresented: $showingStagePicker) {
                QuickStagePickerView()
            }
            .sheet(isPresented: $showingSchedulePicker) {
                QuickSchedulePickerView()
            }
            .sheet(
                item: $eventToEdit
            ) { event in
                EditScheduleEventView(
                    event: event
                )
            }
            .sheet(item: $stewardRouter.request) { request in
                StewardNotificationDestination(request: request)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { _ = await StewardReminderManager.synchronize(modelContext) } }
            }
            .onChange(of: stages.count) { _, _ in
                Task { _ = await StewardReminderManager.synchronize(modelContext) }
            }
            .task {
                await NotificationManager.shared
                    .requestPermission()
                _ = await StewardReminderManager.synchronize(modelContext)
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

                ForEach(SchedulePresentation.todayStages(stages, now: now).filter { $0.isInterested }) { stage in
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
                                        stage.participationTitle,
                                        systemImage:
                                            stage.participation.symbol
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

                        if let interrupted = stage.scheduleEvents.first(where: { $0.isRace && $0.status == "red_flag" }) {
                            NavigationLink {
                                StageDetailView(stage: stage)
                            } label: {
                                Label("КРАСНЫЙ ФЛАГ · \(interrupted.groupID ?? interrupted.title)",
                                      systemImage: "flag.fill")
                                    .foregroundStyle(.red)
                            }
                        }

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

                let otherStages = SchedulePresentation.todayStages(stages, now: now).filter { !$0.isInterested }
                if !otherStages.isEmpty {
                    Section("Сегодня · другие соревнования") {
                        ForEach(otherStages) { stage in
                            NavigationLink { StageDetailView(stage: stage) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(stage.season?.championship?.name ?? "") · \(stage.name)")
                                    Text("\(stage.participationTitle) · \(stage.circuit?.shortName ?? "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // MARK: - Предстоящие этапы

                Section("Предстоящие этапы") {

                    let allUpcoming = allUpcomingStages(now: now).filter { Calendar.current.startOfDay(for: $0.startDate) > Calendar.current.startOfDay(for: now) }
                    let upcoming = Array(allUpcoming.prefix(5))

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

                        NavigationLink {
                            UpcomingStagesView()
                        } label: {
                            Label("Все предстоящие этапы", systemImage: "calendar")
                        }
                    }
                }

                if allUpcomingStages(now: now).filter({ Calendar.current.startOfDay(for: $0.startDate) > Calendar.current.startOfDay(for: now) }).isEmpty {
                    Section {
                        NavigationLink { UpcomingStagesView() } label: {
                            Label("Текущие и предстоящие этапы", systemImage: "calendar")
                        }
                    }
                }
                Section("Гоночные серии") {
                    ChampionshipTiles(championships: championships) { championship in
                        guard championshipToOpen == nil else { return }
                        championshipToOpen = championship
                    }
                    NavigationLink("Все серии · поиск") { ChampionshipCatalogView() }
                }

                Section("Управление") {
                    NavigationLink { ReferenceDataView() } label: {
                        Label("Редактировать справочники", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { DiagnosticsView() } label: {
                        Label("Диагностика", systemImage: "stethoscope")
                    }
                }

            NavigationLink {
                ReleaseHistoryView()
            } label: {
                Text("Версия \(ReleaseHistory.currentVersion) (\(ReleaseHistory.currentBuild))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Upcoming Stages

    private func allUpcomingStages(now: Date) -> [Stage] {
        SchedulePresentation.upcoming(stages, now: now)
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

            if stage.isInterested {
                Label(stage.participationTitle, systemImage: stage.participation.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }

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
        SchedulePresentation.events(stage).filter {
            Calendar.current.isDate($0.plannedStart, inSameDayAs: now) ||
            ($0.plannedStart <= now && SchedulePresentation.end($0) > now)
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

        guard event.status == "scheduled", event.plannedDuration > 0
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
        SchedulePresentation.current(events, now: now)
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
                displayTime(
                    event.plannedStart
                )
            )
            .font(
                past
                    ? .subheadline
                    : .headline
            )
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .strikethrough(past)
            .foregroundStyle(
                past
                    ? .tertiary
                    : .primary
            )
            .frame(
                width: timeColumnWidth,
                alignment: .leading
            )

            VStack(
                alignment: .leading,
                spacing:
                    past ? 2 : 4
            ) {

                if (isCurrent || isNext), let group = SchedulePresentation.groupTitle(event) {
                    Text(group).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }

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
        "через \(RaceClock.countdown(until: event.plannedStart, now: now))"
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

}

private struct QuickStagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var seasons: [Season]
    @State private var selectedSeason: Season?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(seasons.filter { $0.championship != nil && (search.isEmpty || ($0.championship?.name ?? "").localizedCaseInsensitiveContains(search) || $0.displayName.localizedCaseInsensitiveContains(search)) }.sorted { $0.year > $1.year }) { season in
                Button("\(season.championship?.name ?? "Чемпионат") · \(season.displayName)") {
                    selectedSeason = season
                }
            }
            .overlay {
                if seasons.isEmpty {
                    ContentUnavailableView("Сначала добавьте чемпионат и сезон", systemImage: "calendar.badge.plus")
                }
            }
            .searchable(text: $search, prompt: "Серия или сезон")
            .navigationTitle("Выберите сезон")
            .toolbar { Button("Закрыть") { dismiss() } }
            .sheet(item: $selectedSeason) { season in
                AddStageView(season: season) { _ in dismiss() }
            }
        }
    }
}

private struct QuickSchedulePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var stages: [Stage]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(stages.filter { $0.season?.championship != nil && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || ($0.season?.championship?.name ?? "").localizedCaseInsensitiveContains(search)) }.sorted { $0.startDate > $1.startDate }) { stage in
                NavigationLink {
                    StageScheduleFilesView(stage: stage)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stage.name)
                        Text("\(stage.season?.championship?.name ?? "") · \(stage.startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Серия или этап")
            .navigationTitle("Выберите этап")
            .toolbar { Button("Закрыть") { dismiss() } }
        }
    }
}
