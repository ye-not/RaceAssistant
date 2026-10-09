import SwiftUI
import SwiftData

struct RaceControlView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var interruptions: [RaceInterruption]

    let race: ScheduleEvent
    @State private var fiveMinuteAt = Calendar.current.date(
        bySetting: .second, value: 0, of: Date().addingTimeInterval(300)) ?? Date().addingTimeInterval(300)
    @State private var remainingMinutes = 30
    @State private var podiumAt = Date()
    @State private var distanceMode: DistanceMode = .unselected
    @State private var totalLaps = 1
    @State private var completedLaps = 0
    @State private var continuationLaps = 1
    @State private var showFlagConfirmation = false
    @State private var errorMessage: String?

    private enum DistanceMode: String, CaseIterable {
        case unselected = "Выберите формат"
        case laps = "По кругам"
        case timed = "По времени"
    }

    private var maximumContinuationLaps: Int { max(0, totalLaps - completedLaps) }
    private var originalDistance: Int? { lapsInTitle(race.title) }
    private var canResume: Bool {
        guard let interruption, interruption.outcomeRaw == "awaiting",
              fiveMinuteAt >= interruption.flaggedAt else { return false }
        switch distanceMode {
        case .unselected: return false
        case .timed: return originalDistance == nil
        case .laps:
            return totalLaps > 0 && (originalDistance == nil || totalLaps == originalDistance) &&
                completedLaps >= 0 &&
                completedLaps < totalLaps && continuationLaps > 0 &&
                continuationLaps <= maximumContinuationLaps
        }
    }

    private var interruption: RaceInterruption? {
        interruptions.first { $0.raceID == race.notificationID }
    }

    private var podium: ScheduleEvent? {
        guard let stage = race.stage, let group = race.groupID else { return nil }
        return stage.scheduleEvents
            .filter {
                $0.groupID == group &&
                Calendar.current.isDate($0.plannedStart, inSameDayAs: race.plannedStart) &&
                $0.plannedStart >= race.plannedStart &&
                ($0.title.localizedCaseInsensitiveContains("награжд") ||
                 $0.title.localizedCaseInsensitiveContains("подиум") ||
                 $0.title.localizedCaseInsensitiveContains("podium") ||
                 $0.title.localizedCaseInsensitiveContains("award"))
            }
            .min { $0.plannedStart < $1.plannedStart }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Гонка") {
                    Text(race.groupID ?? race.title)
                    LabeledContent("Плановый старт", value: RaceClock.time(race.plannedStart))
                }

                if let interruption {
                    Section("Красный флаг") {
                        LabeledContent("Объявлен", value: interruption.flaggedAt.formatted(date: .abbreviated, time: .shortened))
                        switch interruption.outcomeRaw {
                        case "awaiting": Text("Ожидается решение руководителя гонки")
                        case "ended": Text("Гонка завершена")
                        case "resumed": Text("Продолжение назначено")
                        default: Text("Статус требует проверки")
                        }
                        if interruption.plannedLaps > 0, interruption.outcomeRaw == "resumed" {
                            LabeledContent("Завершено до остановки", value: "\(interruption.completedLaps) кр.")
                            LabeledContent("Назначено на продолжение", value: "\(interruption.continuationLaps) кр.")
                            LabeledContent("Исходная дистанция", value: "\(interruption.plannedLaps) кр.")
                        }
                    }

                    if interruption.outcomeRaw == "awaiting" {
                        Section("Дистанция") {
                            Picker("Формат гонки", selection: $distanceMode) {
                                ForEach(DistanceMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                        .disabled(mode == .timed && originalDistance != nil)
                                }
                            }
                            if distanceMode == .laps {
                                if let originalDistance {
                                    LabeledContent("Исходная дистанция", value: "\(originalDistance) кр.")
                                } else {
                                    Stepper("Исходно: \(totalLaps) кр.", value: $totalLaps, in: 1...500)
                                }
                                Stepper("Завершено до флага: \(completedLaps) кр.",
                                        value: $completedLaps, in: 0...totalLaps)
                                Text("Лимит продолжения: \(maximumContinuationLaps) кр.")
                                    .fontWeight(.semibold)
                                if maximumContinuationLaps > 0 {
                                    Stepper("Продолжить: \(continuationLaps) кр.",
                                            value: $continuationLaps,
                                            in: 1...maximumContinuationLaps)
                                } else {
                                    Text("Вся исходная дистанция уже пройдена. Завершите гонку.")
                                        .foregroundStyle(.secondary)
                                }
                            } else if distanceMode == .timed {
                                Text(originalDistance == nil
                                     ? "Лимит кругов не указан; задайте время продолжения ниже."
                                     : "Для этой гонки указана дистанция в кругах. Запишите число завершённых кругов и остаток дистанции.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            DatePicker("Команда «5 минут»", selection: $fiveMinuteAt,
                                       displayedComponents: [.date, .hourAndMinute])
                            Stepper("Остаток: \(remainingMinutes) мин", value: $remainingMinutes, in: 1...600)
                            Button("Назначить продолжение") { resume(interruption) }
                                .disabled(!canResume)
                        } header: {
                            Text("Продолжить гонку")
                        } footer: {
                            Text("Новая предстартовая последовательность добавится к расписанию. Уже прошедшие события и выезды SC останутся на месте.")
                        }
                        Section {
                            Button("Гонка не будет продолжена", role: .destructive) {
                                finish(interruption)
                            }
                        }
                    } else if interruption.outcomeRaw == "ended", let podium {
                        Section("Награждение") {
                            DatePicker("Новое время", selection: $podiumAt,
                                       displayedComponents: [.date, .hourAndMinute])
                            Button("Изменить время награждения") { updatePodium(podium) }
                        }
                    }
                } else {
                    Section {
                        Button("Объявить красный флаг", role: .destructive) {
                            showFlagConfirmation = true
                        }
                        .disabled(race.status != "scheduled" || race.plannedStart > .now)
                    } header: {
                        Text("Действие")
                    } footer: {
                        Text("Красный флаг остановит отображение текущей гонки до решения о продолжении.")
                    }
                }
            }
            .navigationTitle("Управление гонкой")
            .toolbar { Button("Закрыть") { dismiss() } }
            .onAppear {
                if let podium { podiumAt = podium.plannedStart }
                if let interruption {
                    remainingMinutes = max(1, race.plannedDuration - (race.actualDuration ?? 0))
                    let next = Date().addingTimeInterval(300)
                    fiveMinuteAt = max(Calendar.current.date(bySetting: .second, value: 0, of: next) ?? next,
                                       interruption.flaggedAt)
                    totalLaps = max(1, interruption.plannedLaps)
                    completedLaps = interruption.completedLaps
                    continuationLaps = max(1, interruption.plannedLaps - interruption.completedLaps)
                    if interruption.plannedLaps > 0 { distanceMode = .laps }
                } else if let laps = lapsInTitle(race.title) {
                    totalLaps = laps
                    continuationLaps = laps
                    distanceMode = .laps
                }
            }
            .onChange(of: totalLaps) { _, _ in
                completedLaps = min(completedLaps, totalLaps)
                continuationLaps = max(1, maximumContinuationLaps)
            }
            .onChange(of: completedLaps) { _, _ in
                continuationLaps = max(1, maximumContinuationLaps)
            }
            .confirmationDialog("Объявить красный флаг?", isPresented: $showFlagConfirmation) {
                Button("Объявить красный флаг", role: .destructive) { flag() }
            } message: {
                Text("После остановки выберите продолжение с нового сигнала «5 минут» или завершение гонки.")
            }
            .alert("Не удалось изменить гонку", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func flag() {
        guard interruption == nil, race.isRace, race.status == "scheduled",
              race.plannedStart <= .now, let stage = race.stage else { return }
        let now = Date()
        let start = race.actualStart ?? race.plannedStart
        race.actualStart = start
        race.actualDuration = max(0, Int(now.timeIntervalSince(start) / 60))
        race.status = "red_flag"
        for period in race.safetyCarPeriods where period.isActive {
            period.endedAt = now
            period.isRunning = false
        }
        let record = RaceInterruption(raceID: race.notificationID,
                                      flaggedAt: now, originalPlannedStart: race.plannedStart,
                                      plannedLaps: lapsInTitle(race.title) ?? 0)
        modelContext.insert(record)
        persist(stage)
    }

    private func finish(_ record: RaceInterruption) {
        guard record.outcomeRaw == "awaiting", let stage = race.stage else { return }
        record.outcomeRaw = "ended"
        race.status = "finished"
        persist(stage)
    }

    private func resume(_ record: RaceInterruption) {
        guard canResume, record.outcomeRaw == "awaiting",
              let stage = race.stage else { return }
        let sameDay = Calendar.current
        let members = stage.scheduleEvents.filter {
            race.groupID != nil && $0.groupID == race.groupID &&
            sameDay.isDate($0.plannedStart, inSameDayAs: race.plannedStart)
        }
        let signal = members.filter {
            $0.plannedStart < race.plannedStart &&
            ($0.title.localizedCaseInsensitiveContains("5 минут") ||
             $0.title.localizedCaseInsensitiveContains("5 min"))
        }.max { $0.plannedStart < $1.plannedStart }

        if let signal {
            for template in members.filter({
                !$0.isRace && $0.plannedStart >= signal.plannedStart &&
                $0.plannedStart < race.plannedStart
            }).sorted(by: { $0.plannedStart < $1.plannedStart }) {
                let start = fiveMinuteAt.addingTimeInterval(
                    template.plannedStart.timeIntervalSince(signal.plannedStart))
                duplicate(template, title: template.title, at: start,
                          duration: template.plannedDuration, isRace: false, stage: stage)
            }
        } else {
            duplicate(race, title: "5 минут", at: fiveMinuteAt,
                      duration: 0, isRace: false, stage: stage)
        }

        let startOffset = signal.map { race.plannedStart.timeIntervalSince($0.plannedStart) } ?? 300
        let raceName = race.groupID ?? race.title
        let newTitle = distanceMode == .laps
            ? "Продолжение · \(raceName) · \(continuationLaps) кругов"
            : "Продолжение · \(raceName)"
        let restart = duplicate(race, title: newTitle,
                                at: fiveMinuteAt.addingTimeInterval(startOffset),
                                duration: remainingMinutes, isRace: true, stage: stage)
        record.outcomeRaw = "resumed"
        record.fiveMinuteAt = fiveMinuteAt
        record.continuationRaceID = restart.notificationID
        record.plannedLaps = distanceMode == .laps ? totalLaps : 0
        record.completedLaps = distanceMode == .laps ? completedLaps : 0
        record.continuationLaps = distanceMode == .laps ? continuationLaps : 0
        race.status = "finished"
        persist(stage)
    }

    private func lapsInTitle(_ title: String) -> Int? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(\d+)\s*(?:круг(?:ов|а)?|laps?)"#,
            options: [.caseInsensitive]),
              let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let range = Range(match.range(at: 1), in: title) else { return nil }
        return Int(title[range])
    }

    @discardableResult
    private func duplicate(_ source: ScheduleEvent, title: String, at start: Date,
                           duration: Int, isRace: Bool, stage: Stage) -> ScheduleEvent {
        let copy = ScheduleEvent(title: title, plannedStart: start, plannedDuration: duration,
                                 stage: stage, isRace: isRace, groupID: source.groupID,
                                 remind10Minutes: source.remind10Minutes,
                                 remind5Minutes: source.remind5Minutes,
                                 remind1Minute: source.remind1Minute)
        copy.circuitConfiguration = isRace ? source.effectiveConfiguration : nil
        modelContext.insert(copy)
        stage.scheduleEvents.append(copy)
        for role in source.eventRoles.compactMap(\.role) {
            let link = EventRole(scheduleEvent: copy, role: role)
            modelContext.insert(link)
            copy.eventRoles.append(link)
        }
        for raceClass in source.eventClasses.compactMap(\.raceClass) {
            let link = EventClass(scheduleEvent: copy, raceClass: raceClass)
            modelContext.insert(link)
            copy.eventClasses.append(link)
        }
        return copy
    }

    private func updatePodium(_ podium: ScheduleEvent) {
        guard interruption?.outcomeRaw == "ended", let stage = race.stage else { return }
        podium.plannedStart = podiumAt
        persist(stage)
    }

    private func persist(_ stage: Stage) {
        do {
            try modelContext.save()
            Task {
                await NotificationManager.shared.rescheduleNotifications(for: stage)
                PhoneWatchConnectivityManager.shared.send(stage: stage)
            }
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
