import UIKit
import CarPlay
import SwiftData

@MainActor
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private weak var interfaceController: CPInterfaceController?
    private var overview: CPListTemplate?
    private var scheduleTemplate: CPListTemplate?
    private var scTemplate: CPListTemplate?
    private var dayTemplate: CPListTemplate?
    private var schemeTemplate: CPListTemplate?
    private var schemeTask: Task<Void, Never>?
    private var timer: Timer?
    private var overviewItems: [CPListItem] = []
    private var scItems: [String: CPListItem] = [:]
    private var scSignature = ""
    private var stageSignature = ""
    private var transitionPending = false
    private var overviewIsSchedule = false
    private var expandedScheduleDays = Set<Date>()
    private var schedulePageOffset = 0
    private var scheduleStageID: PersistentIdentifier?
    private var scheduleContentSignature = ""
    private var workButtonsSignature = ""

    private var context: ModelContext { AppModelContainer.shared.mainContext }
    private var workingStage: Stage? {
        let stages = (try? context.fetch(FetchDescriptor<Stage>())) ?? []
        let now = Date()

        if let current = SchedulePresentation.workingStage(stages, now: now) {
            return current
        }

        let today = Calendar.current.startOfDay(for: now)

        let futureWork = stages
            .filter { stage in
                stage.season?.championship != nil &&
                stage.participation == .official && stage.myRole != nil &&
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
        return SchedulePresentation.todayStages(stages, now: now).first {
            !$0.scheduleEvents.isEmpty
        } ?? futureWork ?? SchedulePresentation.upcoming(stages, now: now).first { !$0.scheduleEvents.isEmpty }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        CarPlayDiagnostics.shared.connected = true
        let template = CPListTemplate(title: seriesTitle(workingStage), sections: [])
        template.trailingNavigationBarButtons = [
            CPBarButton(title: "Расписание") { [weak self] _ in self?.openSchedule() },
            CPBarButton(title: "SC") { [weak self] _ in self?.openSC() }
        ]
        template.leadingNavigationBarButtons = [CPBarButton(title: "Трасса") { [weak self] _ in self?.openCircuitScheme() }]
        overview = template
        refresh()
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CarPlayDiagnostics.shared.connected = false
        timer?.invalidate(); timer = nil
        schemeTask?.cancel(); schemeTask = nil
        dayTemplate = nil; schemeTemplate = nil
        overview = nil; scheduleTemplate = nil; scTemplate = nil
        overviewItems = []
        scItems = [:]; scSignature = ""; stageSignature = ""
        transitionPending = false
        overviewIsSchedule = false
        expandedScheduleDays = []; schedulePageOffset = 0; scheduleStageID = nil
        scheduleContentSignature = ""
        workButtonsSignature = ""
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
        let events = stage.map(SchedulePresentation.events) ?? []
        let halted = stage.flatMap { value in
            value.scheduleEvents.first {
                $0.isRace && $0.status == "red_flag" && SchedulePresentation.relevant($0, stage: value)
            }
        }
        let hasWork = stage?.participation == .official && stage?.myRole != nil &&
            (halted != nil || events.contains { $0.plannedStart > now || SchedulePresentation.end($0) > now })
        if !hasWork {
            let signature = stage.map { scheduleSignature($0) } ?? "none"
            if !overviewIsSchedule || signature != scheduleContentSignature {
                overviewIsSchedule = true
                overviewItems = []; stageSignature = ""
                scheduleContentSignature = signature
                configureScheduleDays(stage)
                overview.trailingNavigationBarButtons = []
                workButtonsSignature = ""
                renderSchedule(overview, stage: stage, offset: schedulePageOffset)
            }
            CarPlayDiagnostics.shared.updatedAt = now
            CarPlayDiagnostics.shared.stageName = stage?.name ?? "Не выбран"
            CarPlayDiagnostics.shared.role = stage?.myRole.map(SchedulePresentation.roleName) ?? "Не выбрана"
            CarPlayDiagnostics.shared.currentTitle = "Расписание по дням"
            CarPlayDiagnostics.shared.nextTitle = "Раскройте нужный день"
            refreshSC(stage: stage)
            return
        }
        if overviewIsSchedule {
            overviewIsSchedule = false
            overviewItems = []; stageSignature = ""
        }
        let buttonsSignature = stage.map { "\($0.persistentModelID)|\(SchedulePresentation.isSafetyCar($0.myRole))" } ?? "none"
        if workButtonsSignature != buttonsSignature {
            workButtonsSignature = buttonsSignature
            var buttons = [CPBarButton(title: "Расписание") { [weak self] _ in self?.openSchedule() }]
            if stage.map({ SchedulePresentation.isSafetyCar($0.myRole) }) == true {
                buttons.append(CPBarButton(title: "SC") { [weak self] _ in self?.openSC() })
            }
            overview.trailingNavigationBarButtons = buttons
        }
        let heading = stage.map { stage in
            [stage.name,
             stage.circuit.map { $0.shortName.isEmpty ? $0.name : $0.shortName } ?? "",
             stage.myRole.map(SchedulePresentation.roleName) ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        } ?? "Рабочий этап не выбран"
        if overviewItems.isEmpty || heading != stageSignature {
            overviewItems = [CPListItem(text: "Сейчас", detailText: ""),
                             CPListItem(text: "Следующее", detailText: "")]
            for item in overviewItems { item.handler = { _, completion in completion() } }
            overview.updateSections([CPListSection(items: overviewItems, header: heading, sectionIndexTitle: nil)])
            stageSignature = heading
        }
        let current = SchedulePresentation.current(events, now: now)
        let future = events.filter { $0.plannedStart > now }
        if let halted {
            update(overviewItems[0], text: "КРАСНЫЙ ФЛАГ · \(halted.title)",
                   detail: "\(label(halted)) · ожидание решения о продолжении")
        } else if let current {
            var details = [label(current), RaceClock.duration(minutes: current.plannedDuration)]
            if current.isRace {
                let progress = Int(min(1, max(0, now.timeIntervalSince(current.plannedStart) /
                    max(1, Double(current.plannedDuration) * 60))) * 100)
                details.append("\(progress)%")
            }
            details.append("осталось \(RaceClock.countdown(until: SchedulePresentation.end(current), now: now))")
            update(overviewItems[0], text: "Сейчас · \(current.title)", detail: details.joined(separator: " · "))
        } else if let next = future.first {
            update(overviewItems[0], text: "Следующее · \(next.title)", detail:
                "\(label(next)) · через \(RaceClock.countdown(until: next.plannedStart, now: now))")
        } else {
            update(overviewItems[0], text: stage == nil ? "Выберите рабочую роль на iPhone" : "Работа на этапе завершена",
                   detail: stage == nil ? "CarPlay показывает только этап, где вы официальное лицо" : "Предстоящих событий для роли нет")
        }
        let diagnostic = CarPlayDiagnostics.shared
        diagnostic.updatedAt = now
        diagnostic.stageName = stage?.name ?? "Не выбран"
        diagnostic.role = stage?.myRole.map(SchedulePresentation.roleName) ?? "Не выбрана"
        diagnostic.currentTitle = overviewItems[0].text ?? ""
        let following = halted == nil
            ? (current == nil ? future.dropFirst().first : future.first)
            : nil
        diagnostic.nextTitle = following?.title ?? "Нет"
        if let following {
            var details = [
                label(following),
                time(following, now: now),
                "через \(RaceClock.countdown(until: following.plannedStart, now: now))"
            ]
            if following.plannedDuration > 0 {
                details.append(RaceClock.duration(minutes: following.plannedDuration))
            }
            update(overviewItems[1], text: "\(current == nil ? "Затем" : "Следующее") · \(following.title)",
                   detail: details.joined(separator: " · "))
        } else {
            update(overviewItems[1], text: halted == nil ? "Далее событий нет" : "Расписание уточняется",
                   detail: halted == nil ? "" : "Новый старт пока не назначен")
        }
        refreshSC(stage: stage)
    }

    private func seriesTitle(_ stage: Stage?) -> String {
        let title = stage?.season?.championship?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Race Assistant" : title
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
        // Root → day selector → events: no deeper hierarchy is allowed here.
        guard interfaceController.templates.count < 3 else { return }
        transitionPending = true
        interfaceController.pushTemplate(template, animated: true) { [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.transitionPending = false }
        }
    }

    private func openSchedule() {
        let stage = workingStage
        configureScheduleDays(stage)
        let template = CPListTemplate(title: "Расписание", sections: [])
        scheduleTemplate = template
        renderSchedule(template, stage: stage, offset: 0)
        push(template)
    }

    private func scheduleSignature(_ stage: Stage) -> String {
        let entries = stage.scheduleEvents.sorted { $0.notificationID.uuidString < $1.notificationID.uuidString }
            .map { "\($0.notificationID)|\($0.plannedStart.timeIntervalSince1970)|\($0.plannedDuration)|\($0.title)|\($0.status)" }
        return "\(stage.persistentModelID)|\(stage.name)|\(stage.participationRawValue)|\(stage.myRole?.name ?? "")|\(entries.joined(separator: ";"))"
    }

    private func configureScheduleDays(_ stage: Stage?) {
        guard scheduleStageID != stage?.persistentModelID else { return }
        scheduleStageID = stage?.persistentModelID
        expandedScheduleDays = [Calendar.current.startOfDay(for: .now)]
        schedulePageOffset = 0
    }

    private func resolveStage(_ id: PersistentIdentifier) -> Stage? {
        ((try? context.fetch(FetchDescriptor<Stage>())) ?? []).first { $0.persistentModelID == id }
    }

    private func dayTitle(_ day: Date, today: Date) -> String {
        if Calendar.current.isDate(day, inSameDayAs: today) {
            return "Сегодня · \(day.formatted(.dateTime.day().month()))"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    /// Toggle days in place: no extra templates and no time-interval submenus.
    private func renderSchedule(_ template: CPListTemplate, stage: Stage?, offset: Int) {
        guard let stage else {
            template.updateSections([CPListSection(items: [CPListItem(text: "Нет расписания",
                detailText: "Добавьте этап с расписанием на iPhone")])])
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let grouped = Dictionary(grouping: stage.scheduleEvents) { calendar.startOfDay(for: $0.plannedStart) }
        let stageID = stage.persistentModelID
        var rows: [CPListItem] = []
        for day in grouped.keys.sorted() {
            let events = (grouped[day] ?? []).sorted {
                if $0.plannedStart != $1.plannedStart { return $0.plannedStart < $1.plannedStart }
                return $0.notificationID.uuidString < $1.notificationID.uuidString
            }
            let expanded = expandedScheduleDays.contains(day)
            let range: String
            if let first = events.first, let last = events.map(SchedulePresentation.end).max() {
                range = "\(RaceClock.time(first.plannedStart))–\(RaceClock.time(last))"
            } else { range = "" }
            let header = CPListItem(text: "\(expanded ? "▾" : "▸") \(dayTitle(day, today: today))",
                detailText: "\(events.count) событий · \(range) · \(expanded ? "Свернуть" : "Раскрыть")")
            header.handler = { [weak self, weak template] _, done in
                done()
                guard let self, let template else { return }
                if self.expandedScheduleDays.contains(day) { self.expandedScheduleDays.remove(day) }
                else { self.expandedScheduleDays.insert(day) }
                self.scheduleContentSignature = ""
                self.renderSchedule(template, stage: self.resolveStage(stageID), offset: offset)
            }
            rows.append(header)
            if expanded {
                for event in events {
                    var detail = [SchedulePresentation.groupTitle(event) ?? SchedulePresentation.classes(event)]
                    if event.status == "red_flag" { detail.insert("КРАСНЫЙ ФЛАГ", at: 0) }
                    if event.status == "finished" { detail.insert("Завершено", at: 0) }
                    if event.plannedDuration > 0 { detail.append(RaceClock.duration(minutes: event.plannedDuration)) }
                    let item = CPListItem(text: "\(RaceClock.time(event.plannedStart)) · \(event.title)",
                        detailText: detail.filter { !$0.isEmpty }.joined(separator: " · "))
                    item.handler = { _, done in done() }
                    rows.append(item)
                }
            }
        }
        if rows.isEmpty { rows = [CPListItem(text: "Событий больше нет", detailText: stage.name)] }
        let limit = max(1, CPListTemplate.maximumItemCount)
        let pageSize = rows.count > limit ? max(1, limit - 2) : limit
        let start = max(0, min(offset, max(0, rows.count - 1)))
        let finish = min(rows.count, start + pageSize)
        schedulePageOffset = start
        var page = Array(rows[start..<finish])
        if start > 0, limit >= 3 {
            let previous = CPListItem(text: "← Предыдущие строки", detailText: nil)
            previous.handler = { [weak self, weak template] _, done in
                done()
                guard let self, let template else { return }
                self.renderSchedule(template, stage: self.resolveStage(stageID), offset: max(0, start - pageSize))
            }
            page.insert(previous, at: 0)
        }
        if finish < rows.count, page.count < limit {
            let next = CPListItem(text: "Следующие строки →", detailText: "Ещё \(rows.count - finish)")
            next.handler = { [weak self, weak template] _, done in
                done()
                guard let self, let template else { return }
                self.renderSchedule(template, stage: self.resolveStage(stageID), offset: finish)
            }
            page.append(next)
        }
        template.updateSections([CPListSection(items: page, header: "\(stage.name) · \(seriesTitle(stage))", sectionIndexTitle: nil)])
    }

    private func openCircuitScheme() {
        guard !transitionPending else { return }
        let stage = workingStage
        let configuration = stage?.effectiveConfiguration
        let template = CPListTemplate(title: stage?.circuit?.shortName ?? "Автодром", sections: [
            CPListSection(items: [CPListItem(text: "Схема трассы", detailText: "Загрузка…")])
        ])
        schemeTemplate = template
        push(template)
        schemeTask?.cancel()
        schemeTask = Task { [weak self, weak template] in
            guard let self, let template else { return }
            guard let configuration, let data = configuration.schemeData else {
                template.updateSections([CPListSection(items: [CPListItem(text: "Схема не загружена",
                    detailText: stage?.circuit?.summary ?? "Выберите рабочий этап на iPhone")])])
                return
            }
            do {
                let image = try await CircuitSchemeRenderer.image(data: data, mime: configuration.schemeMIMEType ?? "image/png")
                guard !Task.isCancelled, self.schemeTemplate === template else { return }
                self.showScheme(image, configuration: configuration, template: template)
            } catch {
                guard !Task.isCancelled else { return }
                template.updateSections([CPListSection(items: [CPListItem(text: "Не удалось открыть схему", detailText: error.localizedDescription)])])
            }
        }
    }

    private func showScheme(_ image: UIImage, configuration: CircuitConfiguration, template: CPListTemplate) {
        let row: CPListImageRowItem
        if #available(iOS 26.0, *) {
            let element = CPListImageRowItemGridElement(image: fittedScheme(image, size: CPListImageRowItemGridElement.maximumImageSize))
            row = CPListImageRowItem(text: configuration.name, gridElements: [element], allowsMultipleLines: true)
        } else {
            row = CPListImageRowItem(text: configuration.name, images: [fittedScheme(image, size: CPListImageRowItem.maximumImageSize)])
        }
        row.handler = { _, done in done() }
        row.listImageRowHandler = { _, _, done in done() }
        template.updateSections([CPListSection(items: [row])])
        template.trailingNavigationBarButtons = []
    }

    /// Letterbox to the public template's actual bounds instead of letting it crop a map.
    private func fittedScheme(_ image: UIImage, size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0, image.size.width > 0, image.size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let ratio = min(size.width / image.size.width, size.height / image.size.height)
            let fitted = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2,
                                  width: fitted.width, height: fitted.height))
        }
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
