import UIKit
import CarPlay
import SwiftData

@MainActor
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private weak var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let template = makeRootTemplate()
        interfaceController.setRootTemplate(
            template,
            animated: true,
            completion: nil
        )
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    private func makeRootTemplate() -> CPListTemplate {
        let context = AppModelContainer.shared.mainContext
        let descriptor = FetchDescriptor<ScheduleEvent>(
            sortBy: [SortDescriptor(\.plannedStart)]
        )

        let events = (try? context.fetch(descriptor)) ?? []
        let now = Date()

        let currentEvent = events.first { event in
            guard event.plannedDuration > 0 else { return false }

            let end = event.plannedStart.addingTimeInterval(
                TimeInterval(event.plannedDuration * 60)
            )

            return event.plannedStart <= now && now < end
        }

        let upcomingEvents = events
            .filter { $0.plannedStart > now }
            .prefix(6)

        let stageForTitle =
            currentEvent?.stage ??
            upcomingEvents.first?.stage

        var sections: [CPListSection] = []

        if let currentEvent {
            let item = CPListItem(
                text: currentEvent.title,
                detailText: currentEventDetail(currentEvent, now: now)
            )

            sections.append(
                CPListSection(
                    items: [item],
                    header: "Сейчас",
                    sectionIndexTitle: nil
                )
            )
        } else {
            let item = CPListItem(
                text: "Нет активного события",
                detailText: "Ближайшие события ниже"
            )

            sections.append(
                CPListSection(
                    items: [item],
                    header: "Сейчас",
                    sectionIndexTitle: nil
                )
            )
        }

        let nextItems = upcomingEvents.map { event in
            CPListItem(
                text: event.title,
                detailText: upcomingEventDetail(event)
            )
        }

        if !nextItems.isEmpty {
            sections.append(
                CPListSection(
                    items: nextItems,
                    header: "Далее",
                    sectionIndexTitle: nil
                )
            )
        }

        let template = CPListTemplate(
            title: title(for: stageForTitle),
            sections: sections
        )

        template.emptyViewTitleVariants = ["Нет ближайших событий"]
        template.emptyViewSubtitleVariants = [
            "Расписание появится после импорта данных"
        ]

        return template
    }

    private func title(for stage: Stage?) -> String {
        guard let stage else {
            return "Race Assistant"
        }

        if let circuit = stage.circuit {
            let circuitName =
                circuit.shortName.isEmpty
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

        if event.isRace {
            parts.append(raceProgressText(for: event, now: now))
        } else if event.plannedDuration > 0 {
            parts.append(durationText(minutes: event.plannedDuration))
        }

        if parts.isEmpty {
            parts.append(timeOnlyFormatter.string(from: event.plannedStart))
        }

        return parts.joined(separator: " · ")
    }

    private func upcomingEventDetail(
        _ event: ScheduleEvent
    ) -> String {
        var parts: [String] = [
            timeOnlyFormatter.string(from: event.plannedStart)
        ]

        if let classes = classesText(for: event) {
            parts.append(classes)
        }

        if event.isRace, event.plannedDuration > 0 {
            parts.append(durationText(minutes: event.plannedDuration))
        }

        return parts.joined(separator: " · ")
    }

    private func classesText(
        for event: ScheduleEvent
    ) -> String? {
        let classes = event.eventClasses
            .compactMap { eventClass -> String? in
                guard let raceClass = eventClass.raceClass else {
                    return nil
                }

                if !raceClass.shortName.isEmpty {
                    return raceClass.shortName
                }

                return raceClass.name
            }
            .filter { !$0.isEmpty }

        guard !classes.isEmpty else {
            return nil
        }

        return classes.joined(separator: ", ")
    }

    private func raceProgressText(
        for event: ScheduleEvent,
        now: Date
    ) -> String {
        guard event.plannedDuration > 0 else {
            return "Гонка"
        }

        let elapsedSeconds = max(
            0,
            now.timeIntervalSince(event.plannedStart)
        )

        let totalSeconds =
            TimeInterval(event.plannedDuration * 60)

        let progress = min(
            1,
            elapsedSeconds / totalSeconds
        )

        let percentage =
            Int((progress * 100).rounded())

        let elapsedMinutes =
            Int(elapsedSeconds / 60)

        return "\(elapsedMinutes)/\(event.plannedDuration) мин · \(percentage)%"
    }

    private func durationText(
        minutes: Int
    ) -> String {
        guard minutes >= 60 else {
            return "\(minutes) мин"
        }

        let hours = minutes / 60
        let remainder = minutes % 60

        if remainder == 0 {
            return "\(hours) ч"
        }

        return "\(hours) ч \(remainder) мин"
    }

    private var timeOnlyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}
