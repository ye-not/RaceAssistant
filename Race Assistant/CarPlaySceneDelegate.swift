import UIKit
import CarPlay
import SwiftData

@MainActor
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

        var sections: [CPListSection] = []

        if let currentEvent {
            let item = CPListItem(
                text: currentEvent.title,
                detailText: eventDetail(currentEvent, prefix: "Сейчас")
            )
            sections.append(
                CPListSection(items: [item], header: "Сейчас", sectionIndexTitle: nil)
            )
        } else {
            let item = CPListItem(
                text: "Нет активного события",
                detailText: "Ближайшие события ниже"
            )
            sections.append(
                CPListSection(items: [item], header: "Сейчас", sectionIndexTitle: nil)
            )
        }

        let nextItems = upcomingEvents.map { event in
            CPListItem(
                text: event.title,
                detailText: eventDetail(event, prefix: nil)
            )
        }

        if !nextItems.isEmpty {
            sections.append(
                CPListSection(items: nextItems, header: "Далее", sectionIndexTitle: nil)
            )
        }

        let template = CPListTemplate(
            title: "Race Assistant",
            sections: sections
        )

        template.emptyViewTitleVariants = ["Нет ближайших событий"]
        template.emptyViewSubtitleVariants = ["Расписание появится после импорта данных"]

        return template
    }

    private func eventDetail(
        _ event: ScheduleEvent,
        prefix: String?
    ) -> String {
        var parts: [String] = []

        if let prefix {
            parts.append(prefix)
        }

        parts.append(timeFormatter.string(from: event.plannedStart))

        if let stageName = event.stage?.name,
           !stageName.isEmpty {
            parts.append(stageName)
        }

        return parts.joined(separator: " · ")
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM HH:mm"
        return formatter
    }
}
