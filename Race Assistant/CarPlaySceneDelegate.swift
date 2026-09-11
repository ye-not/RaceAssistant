import UIKit
import CarPlay
import SwiftData

@MainActor
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private weak var interfaceController: CPInterfaceController?
    private var rootTemplate: CPListTemplate?
    private var refreshTimer: Timer?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let template = makeRootTemplate()
        rootTemplate = template

        interfaceController.setRootTemplate(
            template,
            animated: true,
            completion: nil
        )

        startRefreshTimer()
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        rootTemplate = nil
        self.interfaceController = nil
    }

    // MARK: - Auto refresh

    private func startRefreshTimer() {
        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 10,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshContent()
            }
        }
    }

    private func refreshContent() {
        guard let rootTemplate else { return }

        let snapshot = makeRootTemplate()
        rootTemplate.updateSections(snapshot.sections)
    }

    // MARK: - Root

    private func makeRootTemplate() -> CPListTemplate {
        let now = Date()

        guard let stage = workingStage(now: now),
              let role = stage.myRole else {

            let item = CPListItem(
                text: "Рабочий этап не выбран",
                detailText: "Выберите роль на текущем этапе в Race Assistant"
            )

            return CPListTemplate(
                title: "Race Assistant",
                sections: [
                    CPListSection(
                        items: [item],
                        header: "Сейчас",
                        sectionIndexTitle: nil
                    )
                ]
            )
        }

        let events = relevantEvents(
            stage: stage,
            role: role
        )

        let current = currentEvent(
            events,
            now: now
        )

        let future = events.filter {
            $0.plannedStart > now
        }

        let next = future.first
        let later = Array(future.dropFirst().prefix(8))

        var sections: [CPListSection] = []

        if let current {
            sections.append(
                CPListSection(
                    items: [
                        CPListItem(
                            text: current.title,
                            detailText: currentEventDetail(
                                current,
                                now: now
                            )
                        )
                    ],
                    header: "Сейчас · \(roleText(role))",
                    sectionIndexTitle: nil
                )
            )
        } else {
            sections.append(
                CPListSection(
                    items: [
                        CPListItem(
                            text: "Нет активного события",
                            detailText: next == nil
                                ? "На сегодня больше событий нет"
                                : "Ближайшее событие ниже"
                        )
                    ],
                    header: "Сейчас · \(roleText(role))",
                    sectionIndexTitle: nil
                )
            )
        }

        if let next {
            sections.append(
                CPListSection(
                    items: [
                        CPListItem(
                            text: next.title,
                            detailText: nextEventDetail(
                                next,
                                now: now
                            )
                        )
                    ],
                    header: "Следующее",
                    sectionIndexTitle: nil
                )
            )
        }

        if !later.isEmpty {
            let laterItems = later.map { event in
                CPListItem(
                    text: event.title,
                    detailText: upcomingEventDetail(event)
                )
            }

            sections.append(
                CPListSection(
                    items: laterItems,
                    header: "Далее",
                    sectionIndexTitle: nil
                )
            )
        }

        let template = CPListTemplate(
            title: title(for: stage),
            sections: sections
        )

        template.emptyViewTitleVariants = ["Нет ближайших событий"]
        template.emptyViewSubtitleVariants = [
            "Расписание появится после синхронизации"
        ]

        return template
    }

    // MARK: - Working stage

    private func workingStage(now: Date) -> Stage? {
        let context = AppModelContainer.shared.mainContext
        let stages = (try? context.fetch(FetchDescriptor<Stage>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let candidates = stages.filter { stage in
            guard stage.myRole != nil else { return false }

            let start = calendar.startOfDay(for: stage.startDate)
            let end = calendar.startOfDay(for: stage.endDate)

            return today >= start && today <= end
        }

        return candidates.sorted { lhs, rhs in
            let lhsDistance = nextRelevantDistance(stage: lhs, now: now)
            let rhsDistance = nextRelevantDistance(stage: rhs, now: now)

            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            return lhs.startDate < rhs.startDate
        }.first
    }

    private func nextRelevantDistance(
        stage: Stage,
        now: Date
    ) -> TimeInterval {
        guard let role = stage.myRole else {
            return .greatestFiniteMagnitude
        }

        let events = relevantEvents(stage: stage, role: role)

        if currentEvent(events, now: now) != nil {
            return 0
        }

        guard let next = events.first(where: { $0.plannedStart > now }) else {
            return .greatestFiniteMagnitude
        }

        return next.plannedStart.timeIntervalSince(now)
    }

    // MARK: - Role filtering

    private func relevantEvents(
        stage: Stage,
        role: Role
    ) -> [ScheduleEvent] {
        let roleName = roleText(role)
        let isSafetyCar = normalized(roleName) == "sc"

        return stage.scheduleEvents
            .filter { event in
                if event.status == "finished" {
                    return false
                }

                let matchesRole = event.eventRoles.contains { eventRole in
                    guard let eventRoleValue = eventRole.role else {
                        return false
                    }

                    return normalized(roleText(eventRoleValue)) == normalized(roleName)
                }

                // Во время работы Safety Car сама гонка тоже является
                // рабочим текущим событием, даже если в расписании
                // у строки гонки указан только Medical Car.
                if isSafetyCar && event.isRace {
                    return true
                }

                return matchesRole
            }
            .sorted {
                if $0.plannedStart != $1.plannedStart {
                    return $0.plannedStart < $1.plannedStart
                }

                return $0.title < $1.title
            }
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func roleText(_ role: Role) -> String {
        role.shortName.isEmpty ? role.name : role.shortName
    }

    // MARK: - Event state

    private func eventEnd(_ event: ScheduleEvent) -> Date {
        event.plannedStart.addingTimeInterval(
            TimeInterval(event.plannedDuration * 60)
        )
    }

    private func currentEvent(
        _ events: [ScheduleEvent],
        now: Date
    ) -> ScheduleEvent? {
        events.first { event in
            guard event.plannedDuration > 0 else { return false }

            return event.plannedStart <= now && now < eventEnd(event)
        }
    }

    // MARK: - Text

    private func title(for stage: Stage) -> String {
        if let circuit = stage.circuit {
            let circuitName = circuit.shortName.isEmpty
                ? circuit.name
                : circuit.shortName

            if !circuitName.isEmpty {
                return "\(stage.name) · \(circuitName)"
            }
        }

        return stage.name
    }

    private func currentEventDetail(
        _ event: ScheduleEvent,
        now: Date
    ) -> String {
        var parts: [String] = []

        if let classes = classesText(for: event) {
            parts.append(classes)
        }

        if event.plannedDuration > 0 {
            parts.append(durationText(minutes: event.plannedDuration))
            parts.append("осталось \(remainingText(event: event, now: now))")
        }

        if event.isRace, event.plannedDuration > 0 {
            parts.append("\(progressPercent(event: event, now: now))%")
        }

        return parts.joined(separator: " · ")
    }

    private func nextEventDetail(
        _ event: ScheduleEvent,
        now: Date
    ) -> String {
        var parts: [String] = [
            "через \(untilText(event: event, now: now))",
            displayTime(event.plannedStart)
        ]

        if event.plannedDuration > 0 {
            parts.append(durationText(minutes: event.plannedDuration))
        }

        if let classes = classesText(for: event) {
            parts.append(classes)
        }

        return parts.joined(separator: " · ")
    }

    private func upcomingEventDetail(
        _ event: ScheduleEvent
    ) -> String {
        var parts: [String] = [displayTime(event.plannedStart)]

        if event.plannedDuration > 0 {
            parts.append(durationText(minutes: event.plannedDuration))
        }

        if let classes = classesText(for: event) {
            parts.append(classes)
        }

        return parts.joined(separator: " · ")
    }

    private func classesText(
        for event: ScheduleEvent
    ) -> String? {
        let classes = event.eventClasses
            .compactMap { $0.raceClass }
            .map {
                $0.shortName.isEmpty
                    ? $0.name
                    : $0.shortName
            }
            .filter { !$0.isEmpty }
            .sorted()

        return classes.isEmpty
            ? nil
            : classes.joined(separator: ", ")
    }

    private func progressPercent(
        event: ScheduleEvent,
        now: Date
    ) -> Int {
        guard event.plannedDuration > 0 else { return 0 }

        let total = TimeInterval(event.plannedDuration * 60)
        let elapsed = max(0, now.timeIntervalSince(event.plannedStart))
        let progress = min(1, elapsed / total)

        return Int((progress * 100).rounded())
    }

    private func remainingText(
        event: ScheduleEvent,
        now: Date
    ) -> String {
        let seconds = max(0, Int(eventEnd(event).timeIntervalSince(now)))
        return compactInterval(seconds: seconds)
    }

    private func untilText(
        event: ScheduleEvent,
        now: Date
    ) -> String {
        let seconds = max(0, Int(event.plannedStart.timeIntervalSince(now)))
        return compactInterval(seconds: seconds)
    }

    private func compactInterval(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) сек"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60

        if minutes < 2, remainder > 0 {
            return "\(minutes) мин \(remainder) сек"
        }

        if minutes < 60 {
            return "\(minutes) мин"
        }

        let hours = minutes / 60
        let mins = minutes % 60

        return mins == 0
            ? "\(hours) ч"
            : "\(hours) ч \(mins) мин"
    }

    private func durationText(minutes: Int) -> String {
        guard minutes >= 60 else {
            return "\(minutes) мин"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        return remainder == 0
            ? "\(hours) ч"
            : "\(hours) ч \(remainder) мин"
    }

    private func displayTime(_ date: Date) -> String {
        let seconds = Calendar.current.component(.second, from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = seconds == 0 ? "HH:mm" : "HH:mm:ss"
        return formatter.string(from: date)
    }
}
