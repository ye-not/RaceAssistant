import SwiftUI
import SwiftData

struct StageDetailView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \Role.name)
    private var allRoles: [Role]
    
    let stage: Stage
    
    @State private var showingAddScheduleEvent = false
    @State private var eventToEdit: ScheduleEvent?
    @State private var eventToShift: ScheduleEvent?
    
    // Здесь храним дни,
    // которые пользователь раскрыл вручную.
    @State private var expandedCollapsedDays: Set<Date> = []
    
    @State private var showingFullToday = false
    
    // MARK: - Roles
    
    private var activeRoles: [Role] {
        allRoles.filter {
            $0.active
        }
    }
    
    // MARK: - Events
    
    private var sortedEvents: [ScheduleEvent] {
        stage.scheduleEvents.sorted {
            $0.plannedStart < $1.plannedStart
        }
    }
    
    private var groupedEvents: [(date: Date, events: [ScheduleEvent])] {
        let calendar = Calendar.current
        
        let grouped =
        Dictionary(
            grouping: sortedEvents
        ) { event in
            
            calendar.startOfDay(
                for: event.plannedStart
            )
        }
        
        return grouped
            .map {
                (
                    date: $0.key,
                    events: $0.value.sorted {
                        $0.plannedStart <
                            $1.plannedStart
                    }
                )
            }
            .sorted {
                $0.date <
                    $1.date
            }
    }
    // MARK: - Schedule Groups
    
    private func normalizedGroupID(
        _ value: String?
    ) -> String? {
        
        guard let value
        else {
            return nil
        }
        
        let trimmed =
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        
        return trimmed.isEmpty
        ? nil
        : trimmed
    }
    
    private func groupIsRace(
        groupID: String,
        events: [ScheduleEvent]
    ) -> Bool {
        
        events.contains { event in
            
            normalizedGroupID(
                event.groupID
            ) == groupID
            &&
            event.isRace
        }
    }
    // MARK: - Body
    
    var body: some View {
        
        TimelineView(
            .periodic(
                from: .now,
                by: 30
            )
        ) { context in
            
            List {
                
                // MARK: Моя роль
                
                Section("Моя роль") {
                    
                    Picker(
                        "Роль на этапе",
                        selection: roleBinding
                    ) {
                        
                        Text("Не выбрана")
                            .tag(
                                nil as Role?
                            )
                        
                        ForEach(
                            activeRoles
                        ) { role in
                            
                            Text(
                                roleDisplayName(
                                    role
                                )
                            )
                            .tag(
                                role as Role?
                            )
                        }
                    }
                }
                
                // MARK: Уведомления
                
                Section("Уведомления") {
                    
                    Picker(
                        "События",
                        selection:
                            notificationModeBinding
                    ) {
                        
                        ForEach(
                            StageNotificationMode
                                .allCases,
                            id: \.self
                        ) { mode in
                            
                            Text(
                                mode.title
                            )
                            .tag(mode)
                        }
                    }
                    
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        
                        Text(
                            "Напоминать за"
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )
                        
                        HStack(
                            spacing: 12
                        ) {
                            
                            reminderButton(
                                title: "10 мин",
                                isOn:
                                    stage
                                    .stageRemind10Minutes
                            ) {
                                
                                stage
                                    .stageRemind10Minutes
                                    .toggle()
                                
                                notificationSettingsChanged()
                            }
                            
                            reminderButton(
                                title: "5 мин",
                                isOn:
                                    stage
                                    .stageRemind5Minutes
                            ) {
                                
                                stage
                                    .stageRemind5Minutes
                                    .toggle()
                                
                                notificationSettingsChanged()
                            }
                            
                            reminderButton(
                                title: "1 мин",
                                isOn:
                                    stage
                                    .stageRemind1Minute
                            ) {
                                
                                stage
                                    .stageRemind1Minute
                                    .toggle()
                                
                                notificationSettingsChanged()
                            }
                        }
                        .disabled(
                            stage.notificationMode
                            == .none
                        )
                        .opacity(
                            stage.notificationMode
                            == .none
                            ? 0.35
                            : 1.0
                        )
                        
                        if stage.notificationMode
                            == .myRole,
                           stage.myRole == nil {
                            
                            Label(
                                "Для уведомлений по роли сначала выбери свою роль",
                                systemImage:
                                    "exclamationmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                .orange
                            )
                        }
                    }
                    .padding(
                        .vertical,
                        3
                    )
                }
                
                // MARK: Расписание
                
                if sortedEvents.isEmpty {
                    
                    ContentUnavailableView(
                        "Расписание пустое",
                        systemImage:
                            "calendar.badge.clock",
                        description: Text(
                            "Добавь первую строку расписания"
                        )
                    )
                    
                } else {
                    
                    ForEach(
                        groupedEvents,
                        id: \.date
                    ) { group in
                        
                        daySection(
                            date:
                                group.date,
                            events:
                                group.events,
                            now:
                                context.date
                        )
                    }
                }
            }
        }
        .navigationTitle(
            stage.name
        )
        .navigationBarTitleDisplayMode(
            .inline
        )
        
        // MARK: - Toolbar
        
        .toolbar {
            
            ToolbarItem(
                placement:
                        .topBarTrailing
            ) {
                
                Button {
                    showingAddScheduleEvent =
                    true
                } label: {
                    
                    Image(
                        systemName:
                            "plus"
                    )
                }
            }
        }
        
        // MARK: - Add
        
        .sheet(
            isPresented:
                $showingAddScheduleEvent
        ) {
            
            AddScheduleEventView(
                stage: stage
            )
        }
        
        // MARK: - Edit
        
        .sheet(
            item:
                $eventToEdit
        ) { event in
            
            EditScheduleEventView(
                event: event
            )
        }
        
        // MARK: - Shift
        
        .sheet(
            item:
                $eventToShift
        ) { event in
            
            ShiftScheduleView(
                event: event
            )
        }
    }
    
    // MARK: - Notification Mode Binding
    
    private var notificationModeBinding:
    Binding<StageNotificationMode> {
        
        Binding(
            get: {
                stage.notificationMode
            },
            set: { newMode in
                
                stage.notificationMode =
                newMode
                
                notificationSettingsChanged()
            }
        )
    }
    
    // MARK: - Reminder Button
    
    @ViewBuilder
    private func reminderButton(
        title: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        
        Button(
            action: action
        ) {
            
            HStack(
                spacing: 5
            ) {
                
                Image(
                    systemName:
                        isOn
                    ? "checkmark.circle.fill"
                    : "circle"
                )
                
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(
                isOn
                ? .semibold
                : .regular
            )
            .foregroundStyle(
                isOn
                ? Color.orange
                : Color.secondary
            )
            .padding(
                .horizontal,
                10
            )
            .padding(
                .vertical,
                7
            )
            .background {
                
                Capsule()
                    .fill(
                        isOn
                        ? Color.orange
                            .opacity(0.12)
                        : Color.secondary
                            .opacity(0.08)
                    )
            }
        }
        .buttonStyle(
            .plain
        )
    }
    
    // MARK: - Notification Settings Changed
    
    private func notificationSettingsChanged() {
        
        do {
            
            try modelContext.save()
            
            Task {
                
                await NotificationManager
                    .shared
                    .rescheduleNotifications(
                        for: stage
                    )
                
                PhoneWatchConnectivityManager
                    .shared
                    .send(
                        stage: stage
                    )
            }
            
        } catch {
            
            print(
                "Ошибка сохранения настроек уведомлений: \(error)"
            )
        }
    }
    
    // MARK: - Day Section
    
    @ViewBuilder
    private func daySection(
        date: Date,
        events: [ScheduleEvent],
        now: Date
    ) -> some View {
        
        let calendar =
        Calendar.current
        
        let day =
        calendar.startOfDay(
            for: date
        )
        
        let today =
        calendar.startOfDay(
            for: now
        )
        
        let isPastDay =
        day < today
        
        let isToday =
        calendar.isDate(
            day,
            inSameDayAs: today
        )
        
        // Есть ли в этом дне
        // хотя бы одна активность моей роли.
        
        let hasMyEvents =
        dayHasMyEvents(
            events
        )
        
        // Если роль выбрана, но
        // в течение дня ни одной
        // активности этой роли нет —
        // день считаем "не моим".
        
        let isIrrelevantDay =
        stage.myRole != nil
        &&
        !hasMyEvents
        
        // Прошедшие дни и дни без моей роли
        // автоматически сворачиваются.
        
        let shouldAutoCollapse =
        isPastDay
        ||
        isIrrelevantDay
        
        let isManuallyExpanded =
        expandedCollapsedDays
            .contains(day)
        
        // MARK: - Collapsed Day
        
        if shouldAutoCollapse {
            
            Section {
                
                if isManuallyExpanded {
                    
                    eventList(
                        events,
                        now: now,
                        forceDimmed:
                            isIrrelevantDay
                    )
                    
                    Button {
                        toggleCollapsedDay(
                            day
                        )
                    } label: {
                        
                        centeredAction(
                            "Свернуть день",
                            systemImage:
                                "chevron.up"
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    
                } else {
                    
                    Button {
                        toggleCollapsedDay(
                            day
                        )
                    } label: {
                        
                        collapsedDayRow(
                            date: day,
                            events:
                                events,
                            noMyEvents:
                                isIrrelevantDay
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                }
                
            } header: {
                
                if isManuallyExpanded {
                    
                    dayHeader(
                        date: day,
                        isToday:
                            isToday
                    )
                }
            }
        }
        
        // MARK: - Today With My Events
        
        else if isToday {
            
            Section {
                
                let visible =
                showingFullToday
                ? events
                : compactTodayEvents(
                    events,
                    now: now
                )
                
                eventList(
                    visible,
                    now: now,
                    forceDimmed:
                        false
                )
                
                if visible.count <
                    events.count {
                    
                    Button {
                        showingFullToday =
                        true
                    } label: {
                        
                        centeredAction(
                            "Показать весь день",
                            systemImage:
                                "chevron.down"
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                    
                } else if
                    showingFullToday {
                    
                    Button {
                        showingFullToday =
                        false
                    } label: {
                        
                        centeredAction(
                            "Свернуть",
                            systemImage:
                                "chevron.up"
                        )
                    }
                    .buttonStyle(
                        .plain
                    )
                }
                
            } header: {
                
                dayHeader(
                    date: day,
                    isToday:
                        true
                )
            }
        }
        
        // MARK: - Future Day With My Events
        
        else {
            
            Section {
                
                eventList(
                    events,
                    now: now,
                    forceDimmed:
                        false
                )
                
            } header: {
                
                dayHeader(
                    date: day,
                    isToday:
                        false
                )
            }
        }
    }
    
    // MARK: - Day Has My Events
    
    private func dayHasMyEvents(
        _ events: [ScheduleEvent]
    ) -> Bool {
        
        guard stage.myRole != nil
        else {
            return true
        }
        
        return events.contains {
            requiresMyRole(
                $0
            )
        }
    }

    // MARK: - Collapsed Day

    @ViewBuilder
    private func collapsedDayRow(
        date: Date,
        events: [ScheduleEvent],
        noMyEvents: Bool
    ) -> some View {

        HStack {

            VStack(
                alignment: .leading,
                spacing: 4
            ) {

                Text(
                    date.formatted(
                        .dateTime
                            .weekday(
                                .wide
                            )
                            .day()
                            .month(
                                .wide
                            )
                    )
                )
                .font(.headline)
                .foregroundStyle(
                    .primary
                )

                if noMyEvents,
                   let myRole =
                    stage.myRole {

                    Text(
                        "Нет активностей для \(shortRoleName(myRole))"
                    )
                    .font(.caption)
                    .fontWeight(
                        .semibold
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                HStack(
                    spacing: 6
                ) {

                    Text(
                        "\(events.count) событий"
                    )

                    let races =
                        raceCount(
                            in: events
                        )

                    if races > 0 {

                        Text("·")

                        Text(
                            raceCountText(
                                races
                            )
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(
                    .tertiary
                )
            }

            Spacer()

            Image(
                systemName:
                    "chevron.down"
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
        .padding(
            .vertical,
            3
        )
    }

    // MARK: - Day Header

    @ViewBuilder
    private func dayHeader(
        date: Date,
        isToday: Bool
    ) -> some View {

        HStack {

            Text(
                date.formatted(
                    .dateTime
                        .weekday(
                            .wide
                        )
                        .day()
                        .month(
                            .wide
                        )
                )
            )

            if isToday {

                Text("·")

                Text(
                    "СЕГОДНЯ"
                )
                .fontWeight(
                    .semibold
                )
            }
        }
    }

    // MARK: - Today Compact List

    private func compactTodayEvents(
        _ events: [ScheduleEvent],
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

                    !isPast(
                        $0,
                        now: now
                    )
                    &&
                    !isCurrent(
                        $0,
                        now: now
                    )
                    &&
                    $0.plannedStart
                        > now
                }
                .prefix(5)

        // Если гонка входит в группу,
        // оставляем видимой всю группу,
        // а не только строку "Старт гонки".

        let raceGroupIDs =
            Set(
                events
                    .filter {
                        $0.isRace
                    }
                    .compactMap {
                        normalizedGroupID(
                            $0.groupID
                        )
                    }
            )

        let races =
            events.filter { event in

                if event.isRace
                    &&
                    normalizedGroupID(
                        event.groupID
                    ) == nil {

                    return true
                }

                guard let groupID =
                    normalizedGroupID(
                        event.groupID
                    )
                else {
                    return false
                }

                return raceGroupIDs
                    .contains(groupID)
            }

        var result:
            [ScheduleEvent] = []

        appendUnique(
            Array(past),
            to: &result
        )

        appendUnique(
            current,
            to: &result
        )

        appendUnique(
            Array(future),
            to: &result
        )

        appendUnique(
            races,
            to: &result
        )

        return result.sorted {
            $0.plannedStart <
            $1.plannedStart
        }
    }

    private func appendUnique(
        _ events: [ScheduleEvent],
        to result:
            inout [ScheduleEvent]
    ) {

        for event in events {

            if !result.contains(
                where: {
                    $0 === event
                }
            ) {

                result.append(
                    event
                )
            }
        }
    }

    // MARK: - Toggle Collapsed Day

    private func toggleCollapsedDay(
        _ date: Date
    ) {

        let day =
            Calendar.current
                .startOfDay(
                    for: date
                )

        if expandedCollapsedDays
            .contains(day) {

            expandedCollapsedDays
                .remove(day)

        } else {

            expandedCollapsedDays
                .insert(day)
        }
    }

    // MARK: - Event List

    @ViewBuilder
    private func eventList(
        _ events: [ScheduleEvent],
        now: Date,
        forceDimmed: Bool
    ) -> some View {

        ForEach(
            events.indices,
            id: \.self
        ) { index in

            let event =
                events[index]

            let groupID =
                normalizedGroupID(
                    event.groupID
                )

            let previousGroupID: String? =
                index > events.startIndex
                ? normalizedGroupID(
                    events[index - 1].groupID
                )
                : nil

            let nextGroupID: String? =
                index < events.index(
                    before: events.endIndex
                )
                ? normalizedGroupID(
                    events[index + 1].groupID
                )
                : nil

            let showsGroupHeader =
                groupID != nil
                &&
                groupID != previousGroupID

            let closesGroup =
                groupID != nil
                &&
                groupID != nextGroupID

            let raceGroup =
                groupID.map {
                    groupIsRace(
                        groupID: $0,
                        events: events
                    )
                }
                ?? false

            eventButton(
                event,
                now: now,
                forceDimmed: forceDimmed,
                groupTitle:
                    showsGroupHeader
                    ? groupID
                    : nil,
                groupIsRace:
                    raceGroup,
                isGroupEnd:
                    closesGroup
            )
        }
    }
    // MARK: - Event Button

    @ViewBuilder
    private func eventButton(
        _ event: ScheduleEvent,
        now: Date,
        forceDimmed: Bool,
        groupTitle: String? = nil,
        groupIsRace: Bool = false,
        isGroupEnd: Bool = false
    ) -> some View {

        Button {

            eventToEdit =
                event

        } label: {

            eventRow(
                event,
                now: now,
                forceDimmed:
                    forceDimmed,
                groupTitle:
                    groupTitle,
                groupIsRace:
                    groupIsRace,
                isGroupEnd:
                    isGroupEnd
            )
        }
        .buttonStyle(
            .plain
        )
        .swipeActions(
            edge:
                .trailing,
            allowsFullSwipe:
                false
        ) {

            Button(
                role:
                    .destructive
            ) {

                deleteEvent(
                    event
                )

            } label: {

                Label(
                    "Удалить",
                    systemImage:
                        "trash"
                )
            }

            Button {

                eventToEdit =
                    event

            } label: {

                Label(
                    "Изменить",
                    systemImage:
                        "pencil"
                )
            }

            Button {

                eventToShift =
                    event

            } label: {

                Label(
                    "Сдвинуть",
                    systemImage:
                        "clock.arrow.circlepath"
                )
            }
            .tint(
                .orange
            )
        }
    }

    // MARK: - Centered Action

    @ViewBuilder
    private func centeredAction(
        _ title: String,
        systemImage: String
    ) -> some View {

        HStack {

            Spacer()

            Label(
                title,
                systemImage:
                    systemImage
            )
            .font(.footnote)
            .foregroundStyle(
                .secondary
            )

            Spacer()
        }
        .padding(
            .vertical,
            3
        )
    }

    // MARK: - Role Binding

    private var roleBinding:
        Binding<Role?> {

        Binding(
            get: {
                stage.myRole
            },
            set: { newRole in

                stage.myRole =
                    newRole

                // При смене роли снова
                // сворачиваем дни автоматически.

                expandedCollapsedDays =
                    []

                showingFullToday =
                    false

                do {

                    try modelContext
                        .save()

                    Task {

                        await NotificationManager
                            .shared
                            .rescheduleNotifications(
                                for: stage
                            )

                        PhoneWatchConnectivityManager
                            .shared
                            .send(
                                stage: stage
                            )
                    }

                } catch {

                    print(
                        "Ошибка сохранения моей роли: \(error)"
                    )
                }
            }
        )
    }

    // MARK: - Event Row

    @ViewBuilder
        private func eventRow(
            _ event: ScheduleEvent,
            now: Date,
            forceDimmed: Bool,
            groupTitle: String?,
            groupIsRace: Bool,
            isGroupEnd: Bool
        ) -> some View {

        let personal =
            requiresMyRole(
                event
            )

        let hasRoles =
            !event.eventRoles
                .isEmpty

        // Гонки всегда остаются активными.
        //
        // forceDimmed используется,
        // когда пользователь вручную
        // раскрыл день, в котором вообще
        // нет активностей его роли.

        let foreign =
            !event.isRace
            &&
            (
                forceDimmed
                ||
                (
                    stage.myRole != nil
                    &&
                    hasRoles
                    &&
                    !personal
                )
            )

        let current =
            isCurrent(
                event,
                now: now
            )

            VStack(
                alignment: .leading,
                spacing: 6
            ) {

                if let groupTitle {

                    sessionGroupHeader(
                        title: groupTitle,
                        isRace: groupIsRace
                    )
                }
                
        HStack(
            alignment:
                .top,
            spacing:
                foreign
                ? 10
                : 14
        ) {

            // MARK: Время

            VStack(
                alignment:
                    .leading,
                spacing: 3
            ) {

                Text(
                    event.plannedStart
                        .formatted(
                            date:
                                .omitted,
                            time:
                                .shortened
                        )
                )
                .font(
                    foreign
                        ? .subheadline
                        : .headline
                )
                .fontWeight(
                    personal
                        ? .semibold
                        : .regular
                )
                .monospacedDigit()
                .foregroundStyle(
                    personal
                    ? Color.orange
                    : (
                        foreign
                        ? Color.secondary
                        : Color.primary
                    )
                )

                // Время окончания

                if event.plannedDuration
                    > 10 {

                    Text(
                        eventEnd(
                            event
                        )
                        .formatted(
                            date:
                                .omitted,
                            time:
                                .shortened
                        )
                    )
                    .font(
                        .caption2
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        foreign
                            ? .tertiary
                            : .secondary
                    )
                }

                // Гонка

                if event.isRace
                    &&
                    normalizedGroupID(
                        event.groupID
                    ) == nil {

                    Text(
                        "ГОНКА"
                    )
                    .font(
                        .system(
                            size: 9,
                            weight:
                                .bold
                        )
                    )
                    .foregroundStyle(
                        Color.orange
                    )
                    .padding(
                        .horizontal,
                        5
                    )
                    .padding(
                        .vertical,
                        2
                    )
                    .background {

                        Capsule()
                            .fill(
                                Color.orange
                                    .opacity(
                                        0.12
                                    )
                            )
                    }
                    .fixedSize()
                }
            }
            .frame(
                width: 58,
                alignment:
                    .leading
            )

            // MARK: Content

            VStack(
                alignment:
                    .leading,
                spacing:
                    foreign
                    ? 3
                    : 5
            ) {

                // MARK: СЕЙЧАС

                if current {

                    HStack(
                        spacing: 5
                    ) {

                        Circle()
                            .fill(
                                .green
                            )
                            .frame(
                                width: 6,
                                height: 6
                            )

                        Text(
                            "СЕЙЧАС"
                        )
                        .font(
                            .caption2
                        )
                        .fontWeight(
                            .semibold
                        )

                        Text("·")
                            .font(
                                .caption2
                            )

                        Text(
                            remainingTimeText(
                                event:
                                    event,
                                now:
                                    now
                            )
                        )
                        .font(
                            .caption2
                        )
                    }
                    .foregroundStyle(
                        .green
                    )
                }

                // MARK: Title + Duration

                HStack(
                    alignment:
                        .firstTextBaseline,
                    spacing: 7
                ) {

                    Text(
                        event.title
                    )
                    .font(
                        foreign
                            ? .subheadline
                            : .headline
                    )
                    .fontWeight(
                        personal
                            ? .semibold
                            : .regular
                    )
                    .foregroundStyle(
                        personal
                        ? Color.orange
                        : (
                            foreign
                            ? Color.secondary
                            : Color.primary
                        )
                    )
                    .multilineTextAlignment(
                        .leading
                    )

                    Spacer(
                        minLength: 6
                    )

                    if event.plannedDuration
                        > 0 {

                        Text(
                            durationText(
                                event
                                    .plannedDuration
                            )
                        )
                        .font(
                            foreign
                                ? .caption2
                                : .caption
                        )
                        .foregroundStyle(
                            .tertiary
                        )
                        .fixedSize(
                            horizontal:
                                true,
                            vertical:
                                false
                        )
                    }
                }

                // MARK: Classes + Roles

                let classes =
                    classesText(
                        for: event
                    )

                let roles =
                    rolesText(
                        for: event
                    )

                if !classes.isEmpty
                    ||
                    !roles.isEmpty {

                    HStack(
                        alignment:
                            .firstTextBaseline,
                        spacing: 8
                    ) {

                        if !classes
                            .isEmpty {

                            HStack(
                                spacing: 4
                            ) {

                                Image(
                                    systemName:
                                        "car.2"
                                )

                                Text(
                                    classes
                                )
                                .lineLimit(
                                    1
                                )
                            }
                        }

                        Spacer(
                            minLength: 8
                        )

                        if !roles
                            .isEmpty {

                            HStack(
                                spacing: 4
                            ) {

                                Image(
                                    systemName:
                                        "person.2"
                                )

                                Text(
                                    roles
                                )
                                .lineLimit(
                                    1
                                )
                            }
                        }
                    }
                    .font(
                        foreign
                            ? .caption2
                            : .caption
                    )
                    .foregroundStyle(
                        foreign
                            ? .tertiary
                            : .secondary
                    )
                }
            }
        }
    }
    .padding(
        .vertical,
        foreign
            ? 0
            : 2
    )
    .opacity(
        foreign
            ? 0.58
            : 1.0
    )
    .padding(
        .leading,
        normalizedGroupID(
            event.groupID
        ) != nil
            ? 9
            : 0
    )
    .padding(
        .bottom,
        isGroupEnd
            ? 5
            : 0
    )
    .overlay(
        alignment: .leading
    ) {

        if normalizedGroupID(
            event.groupID
        ) != nil {

            Capsule()
                .fill(
                    Color.orange
                        .opacity(0.55)
                )
                .frame(
                    width: 3
                )
        }
    }
    }

    // MARK: - Session Group Header

    @ViewBuilder
    private func sessionGroupHeader(
        title: String,
        isRace: Bool
    ) -> some View {

        HStack(
            alignment: .center,
            spacing: 8
        ) {

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    isRace
                        ? Color.orange
                        : Color.secondary
                )

            Spacer(
                minLength: 8
            )

            if isRace {

                Text("ГОНКА")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        Color.orange
                    )
                    .padding(
                        .horizontal,
                        6
                    )
                    .padding(
                        .vertical,
                        2
                    )
                    .background {

                        Capsule()
                            .fill(
                                Color.orange
                                    .opacity(0.12)
                            )
                    }
            }
        }
    }

    // MARK: - Race Count

    private func raceCount(
        in events: [ScheduleEvent]
    ) -> Int {

        var groupIDs:
            Set<String> = []

        var standaloneRaces =
            0

        for event in events
        where event.isRace {

            if let groupID =
                normalizedGroupID(
                    event.groupID
                ) {

                groupIDs.insert(
                    groupID
                )

            } else {

                standaloneRaces += 1
            }
        }

        return
            groupIDs.count
            +
            standaloneRaces
    }

    // MARK: - Current

    private func isCurrent(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {

        guard
            event.status
                != "finished",
            event.plannedDuration
                > 0
        else {
            return false
        }

        return
            now >=
                event.plannedStart
            &&
            now <
                eventEnd(
                    event
                )
    }

    // MARK: - Past

    private func isPast(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {

        if event.status
            == "finished" {

            return true
        }

        if event.plannedDuration
            == 0 {

            return
                now >=
                event.plannedStart
        }

        return
            now >=
            eventEnd(
                event
            )
    }

    // MARK: - Remaining

    private func remainingTimeText(
        event: ScheduleEvent,
        now: Date
    ) -> String {

        let end =
            eventEnd(
                event
            )

        let seconds =
            end.timeIntervalSince(
                now
            )

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
                "ещё \(minutes) мин"
        }

        let hours =
            minutes / 60

        let remainingMinutes =
            minutes % 60

        if remainingMinutes == 0 {
            return
                "ещё \(hours) ч"
        }

        return
            "ещё \(hours) ч \(remainingMinutes) мин"
    }

    // MARK: - Role

    private func requiresMyRole(
        _ event: ScheduleEvent
    ) -> Bool {

        guard let myRole =
            stage.myRole
        else {
            return false
        }

        guard
            !event.eventRoles
                .isEmpty
        else {
            return false
        }

        return event.eventRoles
            .contains {
                eventRole in

                guard let role =
                    eventRole.role
                else {
                    return false
                }

                return
                    role === myRole
            }
    }

    // MARK: - Event End

    private func eventEnd(
        _ event: ScheduleEvent
    ) -> Date {

        Calendar.current.date(
            byAdding:
                .minute,
            value:
                event.plannedDuration,
            to:
                event.plannedStart
        )
        ??
        event.plannedStart
    }

    // MARK: - Role Display

    private func roleDisplayName(
        _ role: Role
    ) -> String {

        if role.shortName
            .isEmpty {

            return role.name
        }

        return
            "\(role.name) (\(role.shortName))"
    }

    private func shortRoleName(
        _ role: Role
    ) -> String {

        role.shortName.isEmpty
            ? role.name
            : role.shortName
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
                $0.shortName
                    .isEmpty
                ? $0.name
                : $0.shortName
            }
            .sorted()
            .joined(
                separator:
                    " · "
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
                $0.shortName
                    .isEmpty
                ? $0.name
                : $0.shortName
            }
            .sorted()
            .joined(
                separator:
                    " · "
            )
    }

    // MARK: - Duration

    private func durationText(
        _ minutes: Int
    ) -> String {

        if minutes < 60 {
            return
                "\(minutes) мин"
        }

        let hours =
            minutes / 60

        let remainingMinutes =
            minutes % 60

        if remainingMinutes == 0 {
            return
                "\(hours) ч"
        }

        return
            "\(hours) ч \(remainingMinutes) мин"
    }

    // MARK: - Race Count

    private func raceCountText(
        _ count: Int
    ) -> String {

        if count == 1 {
            return
                "1 гонка"
        }

        if count >= 2
            &&
            count <= 4 {

            return
                "\(count) гонки"
        }

        return
            "\(count) гонок"
    }

    // MARK: - Delete

    private func deleteEvent(
        _ event: ScheduleEvent
    ) {

        NotificationManager
            .shared
            .removeNotifications(
                for: event
            )

        modelContext.delete(
            event
        )

        do {

            try modelContext
                .save()

            PhoneWatchConnectivityManager
                .shared
                .send(
                    stage:
                        stage
                )

        } catch {

            print(
                "Ошибка удаления события: \(error)"
            )
        }
    }
}
