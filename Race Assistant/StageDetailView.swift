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

    // Пользовательские переопределения автоматического состояния дней.
    @State private var manuallyExpandedDays: Set<Date> = []
    @State private var manuallyCollapsedDays: Set<Date> = []

    @State private var showingFullToday = false
    
    @State private var showingSafetyCarPanel = false

    private var allSafetyCarPeriods: [SafetyCarPeriod] {
        stage.scheduleEvents.flatMap { $0.safetyCarPeriods }
    }

    private var activeSafetyCarPeriod: SafetyCarPeriod? {
        allSafetyCarPeriods.first { $0.isActive }
    }

    private var safetyCarDeploymentCount: Int {
        allSafetyCarPeriods.count
    }

    private var totalSafetyCarLaps: Int {
        allSafetyCarPeriods.reduce(0) { $0 + $1.lapCount }
    }

    // MARK: - Roles

    private var activeRoles: [Role] {
        allRoles.filter { $0.active }
    }

    // MARK: - Events

    private var sortedEvents: [ScheduleEvent] {
        stage.scheduleEvents.sorted {
            $0.plannedStart < $1.plannedStart
        }
    }

    private var groupedEvents: [(date: Date, events: [ScheduleEvent])] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: sortedEvents) { event in
            calendar.startOfDay(for: event.plannedStart)
        }

        return grouped
            .map {
                (
                    date: $0.key,
                    events: $0.value.sorted {
                        $0.plannedStart < $1.plannedStart
                    }
                )
            }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Schedule Groups

    private func normalizedGroupID(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func groupIsRace(
        groupID: String,
        events: [ScheduleEvent]
    ) -> Bool {
        events.contains { event in
            normalizedGroupID(event.groupID) == groupID && event.isRace
        }
    }

    // MARK: - Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                if stage.myRole?.shortName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("SC") == .orderedSame {

                    Section {
                        Button {
                            showingSafetyCarPanel = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "car.side.fill")
                                    .font(.title2)
                                    .foregroundStyle(
                                        activeSafetyCarPeriod == nil
                                        ? Color.secondary
                                        : Color.orange
                                    )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        activeSafetyCarPeriod == nil
                                        ? "Safety Car"
                                        : "SAFETY CAR АКТИВЕН"
                                    )
                                    .fontWeight(.semibold)
                                    .foregroundStyle(
                                        activeSafetyCarPeriod == nil
                                        ? Color.primary
                                        : Color.orange
                                    )

                                    if let activeSafetyCarPeriod {
                                        Text(
                                            "Текущий выезд: \(activeSafetyCarPeriod.lapCount) кр. · Всего: \(totalSafetyCarLaps) кр."
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } else if safetyCarDeploymentCount > 0 {
                                        Text(
                                            "Выездов: \(safetyCarDeploymentCount) · Кругов: \(totalSafetyCarLaps)"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text("Статистика Safety Car")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Моя роль") {
                    Picker("Роль на этапе", selection: roleBinding) {
                        Text("Не выбрана")
                            .tag(nil as Role?)

                        ForEach(activeRoles) { role in
                            Text(roleDisplayName(role))
                                .tag(role as Role?)
                        }
                    }
                }

                Section("Уведомления") {
                    HStack {
                        Text("События")

                        Spacer()

                        Picker("", selection: notificationModeBinding) {
                            ForEach(StageNotificationMode.allCases, id: \.self) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Напоминать за")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            reminderButton(
                                title: "10 мин",
                                isOn: stage.stageRemind10Minutes
                            ) {
                                stage.stageRemind10Minutes.toggle()
                                notificationSettingsChanged()
                            }

                            reminderButton(
                                title: "5 мин",
                                isOn: stage.stageRemind5Minutes
                            ) {
                                stage.stageRemind5Minutes.toggle()
                                notificationSettingsChanged()
                            }

                            reminderButton(
                                title: "1 мин",
                                isOn: stage.stageRemind1Minute
                            ) {
                                stage.stageRemind1Minute.toggle()
                                notificationSettingsChanged()
                            }

                            Spacer()
                        }
                        .disabled(stage.notificationMode == .none)
                        .opacity(stage.notificationMode == .none ? 0.35 : 1.0)
                    }
                    .padding(.vertical, 3)

                    if stage.notificationMode == .myRole,
                       stage.myRole == nil {
                        Label(
                            "Сначала выбери свою роль",
                            systemImage: "exclamationmark.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                if sortedEvents.isEmpty {
                    ContentUnavailableView(
                        "Расписание пустое",
                        systemImage: "calendar.badge.clock",
                        description: Text("Добавь первую строку расписания")
                    )
                } else {
                    ForEach(groupedEvents, id: \.date) { group in
                        daySection(
                            date: group.date,
                            events: group.events,
                            now: context.date
                        )
                    }
                }
            }
        }
        .navigationTitle(stage.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddScheduleEvent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddScheduleEvent) {
            AddScheduleEventView(stage: stage)
        }
        .sheet(item: $eventToEdit) { event in
            EditScheduleEventView(event: event)
        }
        .sheet(item: $eventToShift) { event in
            ShiftScheduleView(event: event)
        }
        .sheet(isPresented: $showingSafetyCarPanel) {
            SafetyCarPanelView(stage: stage)
        }
    }

    // MARK: - Notification Mode Binding

    private var notificationModeBinding: Binding<StageNotificationMode> {
        Binding(
            get: { stage.notificationMode },
            set: { newMode in
                stage.notificationMode = newMode
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
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.subheadline)
            .fontWeight(isOn ? .semibold : .regular)
            .foregroundStyle(isOn ? Color.orange : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(
                        isOn
                        ? Color.orange.opacity(0.12)
                        : Color.secondary.opacity(0.08)
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification Settings Changed

    private func notificationSettingsChanged() {
        do {
            try modelContext.save()

            Task {
                await NotificationManager.shared.rescheduleNotifications(for: stage)
                PhoneWatchConnectivityManager.shared.send(stage: stage)
            }
        } catch {
            print("Ошибка сохранения настроек уведомлений: \(error)")
        }
    }

    // MARK: - Day Section

    @ViewBuilder
    private func daySection(
        date: Date,
        events: [ScheduleEvent],
        now: Date
    ) -> some View {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)

        let isPastDay = day < today
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let hasMyEvents = dayHasMyEvents(events)

        let isIrrelevantDay =
            stage.myRole != nil &&
            !hasMyEvents

        let shouldAutoCollapse =
            isPastDay ||
            isIrrelevantDay

        let isManuallyExpanded = manuallyExpandedDays.contains(day)
        let isManuallyCollapsed = manuallyCollapsedDays.contains(day)

        let isCollapsed =
            isManuallyCollapsed ||
            (shouldAutoCollapse && !isManuallyExpanded)

        if isCollapsed {
            Section {
                Button {
                    expandDay(day)
                } label: {
                    collapsedDayRow(
                        date: day,
                        events: events
                    )
                }
                .buttonStyle(.plain)
            }
        } else if isToday {
            Section {
                let visible =
                    showingFullToday
                    ? events
                    : compactTodayEvents(events, now: now)

                eventList(
                    visible,
                    now: now,
                    forceDimmed: false
                )

                if visible.count < events.count {
                    Button {
                        showingFullToday = true
                    } label: {
                        centeredAction(
                            "Показать весь день",
                            systemImage: "chevron.down"
                        )
                    }
                    .buttonStyle(.plain)
                } else if showingFullToday {
                    Button {
                        showingFullToday = false
                    } label: {
                        centeredAction(
                            "Свернуть список",
                            systemImage: "chevron.up"
                        )
                    }
                    .buttonStyle(.plain)
                }

            } header: {
                dayHeader(
                    date: day,
                    isToday: true
                ) {
                    collapseDay(day)
                }
            }
        } else {
            Section {
                eventList(
                    events,
                    now: now,
                    forceDimmed: isIrrelevantDay
                )

                Button {
                    collapseDay(day)
                } label: {
                    centeredAction(
                        "Свернуть день",
                        systemImage: "chevron.up"
                    )
                }
                .buttonStyle(.plain)
            } header: {
                dayHeader(
                    date: day,
                    isToday: false
                ) {
                    collapseDay(day)
                }
            }
        }
    }

    // MARK: - Day Has My Events

    private func dayHasMyEvents(_ events: [ScheduleEvent]) -> Bool {
        guard stage.myRole != nil else {
            return true
        }

        return events.contains {
            requiresMyRole($0)
        }
    }

    // MARK: - Collapsed Day

    @ViewBuilder
    private func collapsedDayRow(
        date: Date,
        events: [ScheduleEvent]
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    date.formatted(
                        .dateTime
                            .weekday(.wide)
                            .day()
                            .month(.wide)
                    )
                )
                .font(.headline)
                .foregroundStyle(.primary)

                HStack(
                    spacing: 6
                ) {
                    
                    if let myRole = stage.myRole {
                        
                        let myEvents =
                            events.filter {
                                requiresMyRole($0)
                            }
                        
                        if myEvents.isEmpty {
                            
                            Text(
                                "Нет активностей для \(shortRoleName(myRole))"
                            )
                            
                        } else {
                            
                            Text(
                                "\(myEvents.count) для \(shortRoleName(myRole))"
                            )
                        }
                        
                    } else {
                        
                        Text(
                            eventCountText(
                                events.count
                            )
                        )
                    }
                    
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
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Day Header

    @ViewBuilder
    private func dayHeader(
        date: Date,
        isToday: Bool,
        onCollapse: @escaping () -> Void
    ) -> some View {
        
        HStack {
            
            Text(
                date.formatted(
                    .dateTime
                        .weekday(.wide)
                        .day()
                        .month(.wide)
                )
            )
            
            if isToday {
                
                Text("·")
                
                Text("СЕГОДНЯ")
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            Button {
                onCollapse()
            } label: {
                
                Image(
                    systemName:
                        "chevron.up.circle"
                )
                .font(.body)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
    // MARK: - Today Compact List

    private func compactTodayEvents(
        _ events: [ScheduleEvent],
        now: Date
    ) -> [ScheduleEvent] {
        let past =
            events
                .filter { isPast($0, now: now) }
                .suffix(2)

        let current =
            events
                .filter { isCurrent($0, now: now) }

        let future =
            events
                .filter {
                    !isPast($0, now: now) &&
                    !isCurrent($0, now: now) &&
                    $0.plannedStart > now
                }
                .prefix(5)

        let raceGroupIDs =
            Set(
                events
                    .filter { $0.isRace }
                    .compactMap {
                        normalizedGroupID($0.groupID)
                    }
            )

        let races =
            events.filter { event in
                if event.isRace &&
                    normalizedGroupID(event.groupID) == nil {
                    return true
                }

                guard let groupID = normalizedGroupID(event.groupID) else {
                    return false
                }

                return raceGroupIDs.contains(groupID)
            }

        var result: [ScheduleEvent] = []

        appendUnique(Array(past), to: &result)
        appendUnique(current, to: &result)
        appendUnique(Array(future), to: &result)
        appendUnique(races, to: &result)

        return result.sorted {
            $0.plannedStart < $1.plannedStart
        }
    }

    private func appendUnique(
        _ events: [ScheduleEvent],
        to result: inout [ScheduleEvent]
    ) {
        for event in events {
            if !result.contains(where: { $0 === event }) {
                result.append(event)
            }
        }
    }

    // MARK: - Day Expansion

    private func expandDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)

        manuallyCollapsedDays.remove(day)
        manuallyExpandedDays.insert(day)
    }

    private func collapseDay(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)

        manuallyExpandedDays.remove(day)
        manuallyCollapsedDays.insert(day)
    }

    // MARK: - Event List

    @ViewBuilder
    private func eventList(
        _ events: [ScheduleEvent],
        now: Date,
        forceDimmed: Bool
    ) -> some View {
        ForEach(events.indices, id: \.self) { index in
            let event = events[index]
            let groupID = normalizedGroupID(event.groupID)

            let previousGroupID: String? =
                index > events.startIndex
                ? normalizedGroupID(events[index - 1].groupID)
                : nil

            let nextGroupID: String? =
                index < events.index(before: events.endIndex)
                ? normalizedGroupID(events[index + 1].groupID)
                : nil

            let showsGroupHeader =
                groupID != nil &&
                groupID != previousGroupID

            let closesGroup =
                groupID != nil &&
                groupID != nextGroupID

            let raceGroup =
                groupID.map {
                    groupIsRace(
                        groupID: $0,
                        events: events
                    )
                } ?? false

            eventButton(
                event,
                now: now,
                forceDimmed: forceDimmed,
                groupTitle: showsGroupHeader ? groupID : nil,
                groupIsRace: raceGroup,
                isGroupEnd: closesGroup
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
            eventToEdit = event
        } label: {
            eventRow(
                event,
                now: now,
                forceDimmed: forceDimmed,
                groupTitle: groupTitle,
                groupIsRace: groupIsRace,
                isGroupEnd: isGroupEnd
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteEvent(event)
            } label: {
                Label("Удалить", systemImage: "trash")
            }

            Button {
                eventToEdit = event
            } label: {
                Label("Изменить", systemImage: "pencil")
            }

            Button {
                eventToShift = event
            } label: {
                Label("Сдвинуть", systemImage: "clock.arrow.circlepath")
            }
            .tint(.orange)
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
                systemImage: systemImage
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Role Binding

    private var roleBinding: Binding<Role?> {
        Binding(
            get: {
                stage.myRole
            },
            set: { newRole in
                stage.myRole = newRole

                manuallyExpandedDays = []
                manuallyCollapsedDays = []
                showingFullToday = false

                do {
                    try modelContext.save()

                    Task {
                        await NotificationManager.shared
                            .rescheduleNotifications(for: stage)

                        PhoneWatchConnectivityManager.shared
                            .send(stage: stage)
                    }
                } catch {
                    print("Ошибка сохранения моей роли: \(error)")
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
        let personal = requiresMyRole(event)
        let hasRoles = !event.eventRoles.isEmpty

        let foreign =
            !event.isRace &&
            (
                forceDimmed ||
                (
                    stage.myRole != nil &&
                    hasRoles &&
                    !personal
                )
            )

        let current = isCurrent(event, now: now)

        VStack(alignment: .leading, spacing: 6) {
            if let groupTitle {
                sessionGroupHeader(
                    title: groupTitle,
                    isRace: groupIsRace
                )
            }

            HStack(
                alignment: .top,
                spacing: foreign ? 10 : 14
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        displayTime(
                            event.plannedStart
                        )
                    )
                    .font(foreign ? .subheadline : .headline)
                    .fontWeight(personal ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(
                        personal
                        ? Color.orange
                        : (foreign ? Color.secondary : Color.primary)
                    )

                    if event.plannedDuration > 10 {
                        Text(
                            displayTime(
                                eventEnd(event)
                            )
                        )
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(foreign ? .tertiary : .secondary)
                    }

                    if event.isRace &&
                        normalizedGroupID(event.groupID) == nil {
                        Text("ГОНКА")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(Color.orange.opacity(0.12))
                            }
                            .fixedSize()
                    }
                }
                .frame(width: 58, alignment: .leading)

                VStack(
                    alignment: .leading,
                    spacing: foreign ? 3 : 5
                ) {
                    if current {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)

                            Text("СЕЙЧАС")
                                .font(.caption2)
                                .fontWeight(.semibold)

                            Text("·")
                                .font(.caption2)

                            Text(
                                remainingTimeText(
                                    event: event,
                                    now: now
                                )
                            )
                            .font(.caption2)
                        }
                        .foregroundStyle(.green)
                    }

                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: 7
                    ) {
                        Text(event.title)
                            .font(foreign ? .subheadline : .headline)
                            .fontWeight(personal ? .semibold : .regular)
                            .foregroundStyle(
                                personal
                                ? Color.orange
                                : (foreign ? Color.secondary : Color.primary)
                            )
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 6)

                        if event.plannedDuration > 0 {
                            Text(durationText(event.plannedDuration))
                                .font(foreign ? .caption2 : .caption)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }

                    let classes = classesText(for: event)
                    let roles = rolesText(for: event)

                    if !classes.isEmpty || !roles.isEmpty {
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: 8
                        ) {
                            if !classes.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "car.2")
                                    Text(classes)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 8)

                            if !roles.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2")
                                    Text(roles)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .font(foreign ? .caption2 : .caption)
                        .foregroundStyle(foreign ? .tertiary : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, foreign ? 0 : 2)
        .opacity(foreign ? 0.58 : 1.0)
        .padding(
            .leading,
            normalizedGroupID(event.groupID) != nil ? 9 : 0
        )
        .padding(.bottom, isGroupEnd ? 5 : 0)
        .overlay(alignment: .leading) {
            if normalizedGroupID(event.groupID) != nil {
                Capsule()
                    .fill(Color.orange.opacity(0.55))
                    .frame(width: 3)
            }
        }
    }

    // MARK: - Session Group Header

    @ViewBuilder
    private func sessionGroupHeader(
        title: String,
        isRace: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    isRace ? Color.orange : Color.secondary
                )

            Spacer(minLength: 8)

            if isRace {
                Text("ГОНКА")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                    }
            }
        }
    }

    // MARK: - Race Count

    private func raceCount(
        in events: [ScheduleEvent]
    ) -> Int {
        var groupIDs: Set<String> = []
        var standaloneRaces = 0

        for event in events where event.isRace {
            if let groupID = normalizedGroupID(event.groupID) {
                groupIDs.insert(groupID)
            } else {
                standaloneRaces += 1
            }
        }

        return groupIDs.count + standaloneRaces
    }

    // MARK: - Current

    private func isCurrent(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {
        guard
            event.status != "finished",
            event.plannedDuration > 0
        else {
            return false
        }

        return
            now >= event.plannedStart &&
            now < eventEnd(event)
    }

    // MARK: - Past

    private func isPast(
        _ event: ScheduleEvent,
        now: Date
    ) -> Bool {
        if event.status == "finished" {
            return true
        }

        if event.plannedDuration == 0 {
            return now >= event.plannedStart
        }

        return now >= eventEnd(event)
    }

    // MARK: - Remaining

    private func remainingTimeText(
        event: ScheduleEvent,
        now: Date
    ) -> String {
        let end = eventEnd(event)
        let seconds = end.timeIntervalSince(now)

        let minutes =
            max(
                0,
                Int(ceil(seconds / 60))
            )

        if minutes == 0 {
            return "заканчивается сейчас"
        }

        if minutes < 60 {
            return "ещё \(minutes) мин"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "ещё \(hours) ч"
        }

        return "ещё \(hours) ч \(remainingMinutes) мин"
    }

    // MARK: - Role

    private func requiresMyRole(
        _ event: ScheduleEvent
    ) -> Bool {
        guard let myRole = stage.myRole else {
            return false
        }

        guard !event.eventRoles.isEmpty else {
            return false
        }

        return event.eventRoles.contains { eventRole in
            guard let role = eventRole.role else {
                return false
            }

            return role === myRole
        }
    }

    // MARK: - Event End

    private func eventEnd(
        _ event: ScheduleEvent
    ) -> Date {
        Calendar.current.date(
            byAdding: .minute,
            value: event.plannedDuration,
            to: event.plannedStart
        ) ?? event.plannedStart
    }

    // MARK: - Role Display

    private func roleDisplayName(
        _ role: Role
    ) -> String {
        if role.shortName.isEmpty {
            return role.name
        }

        return "\(role.name) (\(role.shortName))"
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
            .compactMap { $0.raceClass }
            .map {
                $0.shortName.isEmpty
                ? $0.name
                : $0.shortName
            }
            .sorted()
            .joined(separator: " · ")
    }

    // MARK: - Roles

    private func rolesText(
        for event: ScheduleEvent
    ) -> String {
        event.eventRoles
            .compactMap { $0.role }
            .map {
                $0.shortName.isEmpty
                ? $0.name
                : $0.shortName
            }
            .sorted()
            .joined(separator: " · ")
    }

    // MARK: - Duration

    private func durationText(
        _ minutes: Int
    ) -> String {
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

    // MARK: - Event Count Text

    private func eventCountText(
        _ count: Int
    ) -> String {
        
        let mod100 =
            count % 100
        
        let mod10 =
            count % 10
        
        if mod100 >= 11
            &&
            mod100 <= 14 {
            
            return
                "\(count) событий"
        }
        
        if mod10 == 1 {
            
            return
                "\(count) событие"
        }
        
        if mod10 >= 2
            &&
            mod10 <= 4 {
            
            return
                "\(count) события"
        }
        
        return
            "\(count) событий"
    }
    
    // MARK: - Race Count Text

    private func raceCountText(
        _ count: Int
    ) -> String {
        let mod100 = count % 100
        let mod10 = count % 10

        if mod100 >= 11 && mod100 <= 14 {
            return "\(count) гонок"
        }

        switch mod10 {
        case 1:
            return "\(count) гонка"

        case 2...4:
            return "\(count) гонки"

        default:
            return "\(count) гонок"
        }
    }

    // MARK: - Delete

    private func deleteEvent(
        _ event: ScheduleEvent
    ) {
        NotificationManager.shared.removeNotifications(for: event)
        modelContext.delete(event)

        do {
            try modelContext.save()
            PhoneWatchConnectivityManager.shared.send(stage: stage)
        } catch {
            print("Ошибка удаления события: \(error)")
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
