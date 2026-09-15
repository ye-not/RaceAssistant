import UIKit
import CarPlay
import SwiftData

@MainActor
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var overview: CPListTemplate?
    private var upcoming: CPListTemplate?
    private var scTemplate: CPListTemplate?
    private var timer: Timer?
    private var overviewItems: [CPListItem] = []
    private var futureItems: [CPListItem] = []
    private var futureSignature: [UUID] = []
    private var scItems: [String: CPListItem] = [:]
    private var scSignature = ""
    private var stageSignature = ""
    private var transitionPending = false

    private var context: ModelContext { AppModelContainer.shared.mainContext }
    private var workingStage: Stage? {
        let stages = (try? context.fetch(FetchDescriptor<Stage>())) ?? []
        let now = Date()

        if let current = SchedulePresentation.workingStage(stages, now: now) {
            return current
        }

        let today = Calendar.current.startOfDay(for: now)

        return stages
            .filter { stage in
                stage.myRole != nil &&
                !stage.scheduleEvents.isEmpty &&
                Calendar.current.startOfDay(for: stage.startDate) > today
            }
            .sorted {
                if $0.startDate != $1.startDate {
                    return $0.startDate < $1.startDate
                }

                return $0.name < $1.name
            }
            .first
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        let template = CPListTemplate(title: "Race Assistant", sections: [])
        template.trailingNavigationBarButtons = [
            CPBarButton(title: "Далее") { [weak self] _ in self?.openUpcoming() },
            CPBarButton(title: "SC") { [weak self] _ in self?.openSC() }
        ]
        overview = template
        refresh()
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate(); timer = nil
        overview = nil; upcoming = nil; scTemplate = nil
        overviewItems = []; futureItems = []; futureSignature = []
        scItems = [:]; scSignature = ""; stageSignature = ""
        transitionPending = false
        self.interfaceController = nil
    }

    private func update(_ item: CPListItem, text: String, detail: String) {
        if item.text != text { item.setText(text) }
        if item.detailText != detail { item.setDetailText(detail) }
    }

    private func refresh() {
        guard let overview else { return }
        let now = Date()
        let stage = workingStage
        let heading = stage.map { stage in
            [stage.myRole.map(SchedulePresentation.roleName) ?? "", stage.name,
             stage.circuit.map { $0.shortName.isEmpty ? $0.name : $0.shortName } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? "Рабочий этап не выбран"
        if overviewItems.isEmpty || heading != stageSignature {
            overviewItems = [CPListItem(text: "Сейчас", detailText: ""),
                             CPListItem(text: "Следующее", detailText: "")]
            for item in overviewItems { item.handler = { _, completion in completion() } }
            overview.updateSections([CPListSection(items: overviewItems, header: heading, sectionIndexTitle: nil)])
            stageSignature = heading
        }
        let events = stage.map(SchedulePresentation.events) ?? []
        let current = SchedulePresentation.current(events, now: now)
        let future = events.filter { $0.plannedStart > now }
        if let current {
            let progress = Int(min(1, max(0, now.timeIntervalSince(current.plannedStart) /
                max(1, Double(current.plannedDuration) * 60))) * 100)
            update(overviewItems[0], text: "Сейчас · \(label(current))", detail:
                "\(current.title) · \(RaceClock.duration(minutes: current.plannedDuration)) · \(progress)% · осталось \(RaceClock.countdown(until: SchedulePresentation.end(current), now: now))")
        } else if let next = future.first {
            update(overviewItems[0], text: "Следующее · \(label(next))", detail:
                "\(next.title) · через \(RaceClock.countdown(until: next.plannedStart, now: now))")
        } else {
            update(overviewItems[0], text: stage == nil ? "Выберите рабочую роль на iPhone" : "Работа на этапе завершена",
                   detail: stage == nil ? "CarPlay показывает только этап, где вы официальное лицо" : "Предстоящих событий для роли нет")
        }
        let following = current == nil ? future.dropFirst().first : future.first
        if let following {
            update(overviewItems[1], text: "\(current == nil ? "Затем" : "Следующее") · \(label(following))", detail:
                "\(following.title) · \(time(following, now: now)) · через \(RaceClock.countdown(until: following.plannedStart, now: now)) · \(RaceClock.duration(minutes: following.plannedDuration))")
        } else {
            update(overviewItems[1], text: "Далее событий нет", detail: "")
        }
        if let upcoming {
            let visible = Array(future.prefix(CPListTemplate.maximumItemCount))
            let signature = visible.map(\.notificationID)
            if signature != futureSignature || futureItems.isEmpty {
                futureItems = visible.map { event in
                    let item = CPListItem(text: label(event), detailText: "")
                    item.handler = { _, completion in completion() }
                    return item
                }
                let items = futureItems.isEmpty ? [CPListItem(text: "Предстоящих событий нет", detailText: nil)] : futureItems
                upcoming.updateSections([CPListSection(items: items, header: nil, sectionIndexTitle: nil)])
                futureSignature = signature
            }
            for (item, event) in zip(futureItems, visible) {
                update(item, text: label(event), detail: "\(time(event, now: now)) · \(event.title) · \(RaceClock.duration(minutes: event.plannedDuration))")
            }
        }
        refreshSC(stage: stage)
    }

    private func label(_ event: ScheduleEvent) -> String {
        let group = SchedulePresentation.groupTitle(event) ?? SchedulePresentation.classes(event)
        return group.isEmpty ? event.title : group
    }

    private func time(_ event: ScheduleEvent, now: Date) -> String {
        let value = RaceClock.time(event.plannedStart)
        return Calendar.current.isDate(event.plannedStart, inSameDayAs: now)
            ? value : "\(event.plannedStart.formatted(.dateTime.day().month())) · \(value)"
    }

    private func push(_ template: CPTemplate) {
        guard let interfaceController, !transitionPending, interfaceController.topTemplate !== template else { return }
        transitionPending = true
        interfaceController.pushTemplate(template, animated: true) { [weak self] _, _ in
            Task { @MainActor in self?.transitionPending = false }
        }
    }

    private func openUpcoming() {
        if upcoming == nil { upcoming = CPListTemplate(title: "Далее", sections: []) }
        refresh()
        if let upcoming { push(upcoming) }
    }

    private func openSC() {
        if scTemplate == nil { scTemplate = CPListTemplate(title: "Safety Car", sections: []) }
        refresh()
        if let scTemplate { push(scTemplate) }
    }

    private func periods(_ stage: Stage) -> [SafetyCarPeriod] {
        ((try? context.fetch(FetchDescriptor<SafetyCarPeriod>())) ?? [])
            .filter { $0.scheduleEvent?.stage === stage }
    }

    private func refreshSC(stage: Stage?) {
        guard let scTemplate else { return }
        guard let stage, SchedulePresentation.isSafetyCar(stage.myRole) else {
            if scSignature != "unavailable" {
                scTemplate.updateSections([CPListSection(items: [CPListItem(text: "Выберите роль SC на рабочем этапе", detailText: "Настройте роль на iPhone")], header: nil, sectionIndexTitle: nil)])
                scSignature = "unavailable"; scItems = [:]
            }
            return
        }
        let active = periods(stage).first { $0.isActive }
        let race = active?.scheduleEvent ?? SchedulePresentation.current(stage.scheduleEvents.filter { $0.isRace }, now: .now)
        let signature = "\(stage.persistentModelID)|\(race?.notificationID.uuidString ?? "none")|\(active.map { String(describing: $0.persistentModelID) } ?? "idle")"
        if signature != scSignature {
            scItems = [:]
            var items: [CPListItem] = []
            func add(_ key: String, _ title: String, action: (() -> Void)? = nil) {
                let item = CPListItem(text: title, detailText: "")
                item.handler = { _, completion in
                    completion()
                    action?()
                }
                scItems[key] = item; items.append(item)
            }
            add("state", active == nil ? "SC не активен" : "SC АКТИВЕН")
            if let race {
                // Capture stable identifiers, then resolve current models on every tap.
                let id = race.notificationID
                let periodID = active?.persistentModelID
                if active == nil {
                    add("start", "НАЧАТЬ SC") { [weak self] in self?.performSC("start", raceID: id) }
                } else {
                    add("plus", "+ КРУГ") { [weak self] in self?.performSC("plus", raceID: id, periodID: periodID) }
                    add("minus", "− КРУГ") { [weak self] in self?.performSC("minus", raceID: id, periodID: periodID) }
                    add("finish", "ЗАВЕРШИТЬ SC") { [weak self] in self?.performSC("finish", raceID: id, periodID: periodID) }
                    add("cancel", "ОТМЕНИТЬ ВЫЕЗД") { [weak self] in self?.confirmCancel(raceID: id, periodID: periodID) }
                }
            }
            scTemplate.updateSections([CPListSection(items: items, header: nil, sectionIndexTitle: nil)])
            scSignature = signature
        }
        if let item = scItems["state"] {
            update(item, text: active.map { "SC АКТИВЕН · \($0.lapCount) кругов" } ?? "SC не активен",
                   detail: race.map { SchedulePresentation.raceLabel($0) } ?? "Сейчас нет текущей гонки. Историю можно внести на iPhone.")
        }
    }

    private func confirmCancel(raceID: UUID, periodID: PersistentIdentifier?) {
        let alert = CPAlertTemplate(titleVariants: ["Удалить текущий выезд SC?"], actions: [
            CPAlertAction(title: "Удалить выезд", style: .destructive) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
                self?.performSC("cancel", raceID: raceID, periodID: periodID)
            },
            CPAlertAction(title: "Вернуться", style: .cancel) { [weak self] _ in
                self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
            }
        ])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func performSC(_ action: String, raceID: UUID, periodID: PersistentIdentifier? = nil) {
        guard let stage = workingStage, SchedulePresentation.isSafetyCar(stage.myRole),
              let race = stage.scheduleEvents.first(where: { $0.notificationID == raceID }) else { refresh(); return }
        let active = periods(stage).first { $0.isActive }
        if action == "start" {
            guard active == nil, SchedulePresentation.current(stage.scheduleEvents.filter { $0.isRace }, now: .now) === race else { refresh(); return }
            let period = SafetyCarPeriod(startedAt: .now, scheduleEvent: race)
            period.isRunning = true
            context.insert(period)
        } else {
            guard let active, active.scheduleEvent === race, active.persistentModelID == periodID else { refresh(); return }
            switch action {
            case "plus": active.lapCount += 1
            case "minus": active.lapCount = max(0, active.lapCount - 1)
            case "finish": active.isRunning = false
            case "cancel": context.delete(active)
            default: return
            }
        }
        do { try context.save() }
        catch {
            context.rollback()
            let alert = CPAlertTemplate(titleVariants: ["Не удалось сохранить SC", error.localizedDescription], actions: [
                CPAlertAction(title: "OK", style: .default) { [weak self] _ in self?.interfaceController?.dismissTemplate(animated: true, completion: nil) }
            ])
            interfaceController?.presentTemplate(alert, animated: true, completion: nil)
        }
        refresh()
    }
}
