import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject
    private var connectivity:
        WatchConnectivityManager

    var body: some View {

        TimelineView(
            .periodic(
                from: .now,
                by: 1
            )
        ) { context in

            content(
                now:
                    context.date
            )
        }
        .onAppear { connectivity.refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { connectivity.refreshStatus() }
        }
    }

    // MARK: - Root

    @ViewBuilder
    private func content(
        now: Date
    ) -> some View {

        if let schedule =
            connectivity.scheduleData, schedule.stageAvailable != false {

            scheduleView(
                schedule,
                now: now
            )

        } else {

            VStack(
                spacing: 10
            ) {

                Image(
                    systemName:
                        "iphone.and.arrow.forward"
                )
                .font(.title2)
                .foregroundStyle(
                    .secondary
                )

                Text(
                    "Нет расписания"
                )
                .font(.headline)

                Text(
                    "Открой Race Assistant на iPhone"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
                .multilineTextAlignment(
                    .center
                )
                Button("Обновить") { connectivity.refreshStatus() }
                Text(connectivity.isReachable ? "iPhone на связи" : "Ожидание связи с iPhone")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Schedule

    private func scheduleView(
        _ schedule: WatchScheduleData,
        now: Date
    ) -> some View {

        let relevant =
            relevantEvents(
                schedule.events,
                schedule:
                    schedule
            )

        let current =
            currentEvent(
                relevant,
                now: now
            )

        let next =
            nextEvent(
                relevant,
                now: now
            )

        return ScrollView {

            VStack(
                alignment: .leading,
                spacing: 12
            ) {

                headerView(
                    schedule
                )

                Divider()

                if schedule.stewardMode == true {
                    stewardIncidentList(schedule, now: now)
                } else if let redFlagTitle = schedule.redFlagTitle {
                    Label("КРАСНЫЙ ФЛАГ", systemImage: "flag.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                    Text(redFlagTitle).font(.caption)
                    Text("Ожидается решение о продолжении гонки")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if schedule.events.isEmpty {

                    emptyScheduleView()

                } else if
                    !schedule.myRole.isEmpty
                    &&
                    relevant.isEmpty {

                    noRoleEventsView(
                        role:
                            schedule.myRole
                    )

                } else {

                    if let current {

                        currentEventView(
                            current,
                            schedule:
                                schedule,
                            now:
                                now
                        )
                    }

                    if let next {

                        nextEventView(
                            next,
                            schedule:
                                schedule,
                            now:
                                now,
                            label:
                                "ДАЛЕЕ"
                        )

                        if current == nil,
                           let following =
                            followingEvent(
                                relevant,
                                after:
                                    next
                            ) {

                            Divider()

                            nextEventView(
                                following,
                                schedule:
                                    schedule,
                                now:
                                    now,
                                label:
                                    "ПОТОМ"
                            )
                        }
                    }

                    if current == nil
                        &&
                        next == nil {

                        noUpcomingEventsView(
                            schedule:
                                schedule
                        )
                    }
                }
            }
            .padding(
                .horizontal,
                4
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func stewardIncidentList(_ schedule: WatchScheduleData, now: Date) -> some View {
        let incidents = schedule.stewardIncidents ?? []
        Text("КСК · В РАБОТЕ: \(incidents.count)")
            .font(.headline).foregroundStyle(.orange)
        if incidents.isEmpty {
            Text("Нет нерассмотренных инцидентов").font(.caption)
            Text("Создайте инцидент на iPhone.").font(.caption2).foregroundStyle(.secondary)
        } else {
            ForEach(incidents) { incident in
                VStack(alignment: .leading, spacing: 5) {
                    Text(incident.title).font(.headline)
                    Text("\(RaceClock.time(incident.occurredAt)) · \(incident.status)")
                        .font(.caption).foregroundStyle(.orange)
                    if !incident.raceClass.isEmpty { Text(incident.raceClass).font(.caption) }
                    if !incident.driverNumbers.isEmpty {
                        Text("№ \(incident.driverNumbers)").font(.caption)
                    }
                    if !incident.description.isEmpty { Text(incident.description).font(.caption2) }
                    ForEach(incident.tasks) { task in
                        Text("○ \(task.title)").font(.caption2)
                        if let due = task.due {
                            Text(due, format: .dateTime.day().month().hour().minute())
                                .font(.caption2).foregroundStyle(due < now ? Color.red : Color.secondary)
                        }
                    }
                }
                Divider()
            }
            Text("Решения и изменение задач — на iPhone.").font(.caption2).foregroundStyle(.secondary)
        }
        Button("Обновить") { connectivity.refreshStatus() }
    }

    @ViewBuilder
    private func headerView(
        _ schedule: WatchScheduleData
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 4
        ) {

            HStack(
                spacing: 4
            ) {

                Text(
                    schedule.championshipName
                )
                .foregroundStyle(
                    .secondary
                )

                Text("·")
                    .foregroundStyle(
                        .secondary
                    )

                Text(
                    schedule.stageName
                )
                .fontWeight(
                    .semibold
                )
            }
            .font(
                .caption
            )
            .lineLimit(
                1
            )
            .truncationMode(
                .tail
            )

            HStack(
                spacing: 5
            ) {

                if !schedule
                    .circuitName
                    .isEmpty {

                    Image(
                        systemName:
                            "road.lanes"
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Text(
                        schedule.circuitName
                    )
                    .foregroundStyle(
                        .secondary
                    )
                    .lineLimit(
                        1
                    )
                    .truncationMode(
                        .tail
                    )
                }

                Spacer(
                    minLength: 4
                )

                if !schedule
                    .myRole
                    .isEmpty {

                    Text(
                        schedule.myRole
                    )
                    .fontWeight(
                        .bold
                    )
                    .foregroundStyle(
                        .orange
                    )
                    .fixedSize(
                        horizontal: true,
                        vertical: false
                    )
                }
            }
            .font(
                .caption
            )
        }
    }

    // MARK: - Empty Schedule

    @ViewBuilder
    private func emptyScheduleView()
        -> some View {

        VStack(
            spacing: 6
        ) {

            Image(
                systemName:
                    "calendar.badge.exclamationmark"
            )
            .font(.title3)
            .foregroundStyle(
                .secondary
            )

            Text(
                "Расписание пустое"
            )
            .font(.headline)

            Text(
                "Синхронизация выполнена, но событий нет"
            )
            .font(.caption2)
            .foregroundStyle(
                .secondary
            )
            .multilineTextAlignment(
                .center
            )
        }
        .frame(
            maxWidth:
                .infinity
        )
        .padding(
            .top,
            10
        )
    }

    // MARK: - No Events For Role

    @ViewBuilder
    private func noRoleEventsView(
        role: String
    ) -> some View {

        VStack(
            spacing: 6
        ) {

            Image(
                systemName:
                    "person.crop.circle.badge.questionmark"
            )
            .font(.title3)
            .foregroundStyle(
                .secondary
            )

            Text(
                "Нет активностей"
            )
            .font(.headline)

            Text(
                "Для роли \(role) в расписании ничего не найдено"
            )
            .font(.caption2)
            .foregroundStyle(
                .secondary
            )
            .multilineTextAlignment(
                .center
            )
        }
        .frame(
            maxWidth:
                .infinity
        )
        .padding(
            .top,
            10
        )
    }

    // MARK: - No Upcoming Events

    @ViewBuilder
    private func noUpcomingEventsView(
        schedule: WatchScheduleData
    ) -> some View {

        VStack(
            spacing: 6
        ) {

            Image(
                systemName:
                    "checkmark.circle"
            )
            .font(.title3)
            .foregroundStyle(
                .green
            )

            if schedule.myRole.isEmpty {

                Text(
                    "Этап завершён"
                )
                .font(.headline)

                Text(
                    "Предстоящих событий нет"
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )

            } else {

                Text(
                    "Для \(schedule.myRole) всё"
                )
                .font(.headline)

                Text(
                    "Предстоящих активностей нет"
                )
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )
            }
        }
        .frame(
            maxWidth:
                .infinity
        )
        .padding(
            .top,
            10
        )
    }

    // MARK: - Current Event

    private func currentEventView(
        _ event: WatchScheduleItem,
        schedule: WatchScheduleData,
        now: Date
    ) -> some View {

        let personal =
            requiresMyRole(
                event,
                schedule:
                    schedule
            )

        let progress =
            eventProgress(
                event,
                now: now
            )

        return VStack(
            alignment: .leading,
            spacing: 6
        ) {
            if let group = event.groupTitle, !group.isEmpty {
                Text(group).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }

            HStack(
                spacing: 5
            ) {

                Circle()
                    .fill(
                        .green
                    )
                    .frame(
                        width: 7,
                        height: 7
                    )

                Text(
                    "СЕЙЧАС"
                )
                .font(.caption2)
                .fontWeight(
                    .bold
                )

                Spacer()

                Text(
                    remainingText(
                        event,
                        now: now
                    )
                )
                .font(.caption2)
            }
            .foregroundStyle(
                .green
            )

            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 8
            ) {

                Text(
                    timeText(
                        event.start
                    )
                )
                .font(.headline)
                .fontWeight(
                    personal
                        ? .semibold
                        : .regular
                )
                .monospacedDigit()
                .foregroundStyle(
                    personal
                        ? .orange
                        : .primary
                )

                Text(
                    event.title
                )
                .font(.headline)
                .fontWeight(
                    .semibold
                )
                .foregroundStyle(
                    personal
                        ? .orange
                        : .primary
                )
            }

            eventDetails(
                event
            )

            if event.duration > 0 {

                HStack(
                    spacing: 6
                ) {

                    ProgressView(
                        value:
                            progress
                    )
                    .tint(
                        .green
                    )

                    Text(
                        "\(Int(progress * 100))%"
                    )
                    .font(
                        .caption2
                    )
                    .monospacedDigit()
                    .foregroundStyle(
                        .green
                    )
                    .frame(
                        width: 30,
                        alignment:
                            .trailing
                    )
                }
            }
        }
    }

    // MARK: - Next Event

    private func nextEventView(
        _ event: WatchScheduleItem,
        schedule: WatchScheduleData,
        now: Date,
        label: String
    ) -> some View {

        let personal =
            requiresMyRole(
                event,
                schedule:
                    schedule
            )

        let isToday =
            Calendar.current
                .isDate(
                    event.start,
                    inSameDayAs:
                        now
                )

        return VStack(
            alignment: .leading,
            spacing: 6
        ) {
            if let group = event.groupTitle, !group.isEmpty {
                Text(group).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }

            if !isToday {

                Text(
                    event.start
                        .formatted(
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
                .font(.caption2)
                .fontWeight(
                    .semibold
                )
                .foregroundStyle(
                    .secondary
                )
            }

            HStack {

                Text(
                    label
                )
                .font(.caption2)
                .fontWeight(
                    .bold
                )

                Spacer()

                Text(
                    untilText(
                        event,
                        now: now
                    )
                )
                .font(.caption2)
            }
            .foregroundStyle(
                personal
                    ? .orange
                    : .secondary
            )

            HStack(
                alignment:
                    .firstTextBaseline,
                spacing: 8
            ) {

                Text(
                    timeText(
                        event.start
                    )
                )
                .font(.headline)
                .fontWeight(
                    personal
                        ? .semibold
                        : .regular
                )
                .monospacedDigit()
                .foregroundStyle(
                    personal
                        ? .orange
                        : .primary
                )

                Text(
                    event.title
                )
                .font(.headline)
                .fontWeight(
                    personal
                        ? .semibold
                        : .regular
                )
                .foregroundStyle(
                    personal
                        ? .orange
                        : .primary
                )
            }

            eventDetails(
                event
            )
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func eventDetails(
        _ event: WatchScheduleItem
    ) -> some View {

        if !event.classes
            .isEmpty {

            Text(
                event.classes
                    .joined(
                        separator:
                            " · "
                    )
            )
            .font(.caption2)
            .foregroundStyle(
                .secondary
            )
        }

        if event.duration > 5 {

            Text(
                durationText(
                    event.duration
                )
            )
            .font(.caption2)
            .foregroundStyle(
                .secondary
            )
        }
    }

    // MARK: - Relevant Events

    private func relevantEvents(
        _ events: [WatchScheduleItem],
        schedule: WatchScheduleData
    ) -> [WatchScheduleItem] {

        let sorted =
            events.sorted {
                $0.start <
                $1.start
            }

        guard
            !schedule.myRole.isEmpty,
            schedule.participationRawValue == nil || schedule.participationRawValue == "official"
        else {
            return sorted
        }

        let normalizedRole =
            schedule.myRole
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()

        return sorted.filter { event in
            // Для выбранной должности пустой список ролей не означает «всем».
            if event.roles.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedRole
            }) {
                return true
            }

            // Safety Car должен видеть текущую гонку,
            // даже если у самой строки гонки в исходном
            // расписании указан только Medical Car.
            if normalizedRole == "sc",
               event.isRace == true {
                return true
            }

            return false
        }
    }

    // MARK: - Personal Event

    private func requiresMyRole(
        _ event: WatchScheduleItem,
        schedule: WatchScheduleData
    ) -> Bool {

        guard
            !schedule.myRole.isEmpty,
            !event.roles.isEmpty
        else {
            return false
        }

        return event.roles.contains(
            schedule.myRole
        )
    }

    // MARK: - Event End

    private func eventEnd(
        _ event: WatchScheduleItem
    ) -> Date {

        Calendar.current.date(
            byAdding:
                .minute,
            value:
                event.duration,
            to:
                event.start
        )
        ??
        event.start
    }

    // MARK: - Event Progress

    private func eventProgress(
        _ event: WatchScheduleItem,
        now: Date
    ) -> Double {

        guard event.duration > 0 else {
            return 0
        }

        let totalDuration =
            TimeInterval(
                event.duration * 60
            )

        let elapsed =
            now.timeIntervalSince(
                event.start
            )

        return min(
            max(
                elapsed /
                    totalDuration,
                0
            ),
            1
        )
    }

    // MARK: - Current Event

    private func currentEvent(
        _ events: [WatchScheduleItem],
        now: Date
    ) -> WatchScheduleItem? {
        events.filter {
            $0.duration > 0 && $0.start <= now && now < eventEnd($0)
        }.sorted {
            if ($0.isRace == true) != ($1.isRace == true) { return $0.isRace == true }
            return $0.start > $1.start
        }.first
    }

    // MARK: - Next Event

    private func nextEvent(
        _ events: [WatchScheduleItem],
        now: Date
    ) -> WatchScheduleItem? {

        events.first {
            event in

            event.start >
                now
        }
    }

    // MARK: - Following Event

    private func followingEvent(
        _ events: [WatchScheduleItem],
        after event: WatchScheduleItem
    ) -> WatchScheduleItem? {

        events
            .sorted {
                $0.start <
                $1.start
            }
            .first {
                $0.start >
                event.start
            }
    }

    // MARK: - Time

    private func timeText(
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

    // MARK: - Remaining

    private func remainingText(
        _ event: WatchScheduleItem,
        now: Date
    ) -> String {

        let seconds =
            eventEnd(
                event
            )
            .timeIntervalSince(
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
                "заканчивается"
        }

        if minutes < 60 {
            return
                "ещё \(minutes) мин"
        }

        let hours =
            minutes / 60

        let remainder =
            minutes % 60

        if remainder == 0 {
            return
                "ещё \(hours) ч"
        }

        return
            "ещё \(hours) ч \(remainder) мин"
    }

    // MARK: - Until

    private func untilText(
        _ event: WatchScheduleItem,
        now: Date
    ) -> String {
        "через \(RaceClock.countdown(until: event.start, now: now))"
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

        let remainder =
            minutes % 60

        if remainder == 0 {
            return
                "\(hours) ч"
        }

        return
            "\(hours) ч \(remainder) мин"
    }
}
