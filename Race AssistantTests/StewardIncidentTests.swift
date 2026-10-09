import Foundation
import SwiftData
import Testing
@testable import Race_Assistant

@MainActor
struct StewardIncidentTests {
    @Test func watchSnapshotContainsUndecidedIncidentsAndOpenTasksOnly() throws {
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now,
            myRole: Role(name: "Спортивные комиссары", shortName: "КСК"))
        let incident = StewardIncident(title: "Контакт", occurredAt: .now)
        incident.driverNumbers = "007, 23"
        incident.makeRequiredTasks(); incident.startReview()
        let decided = StewardIncident(title: "Решённый", occurredAt: .now)
        decided.makeRequiredTasks(); decided.startReview()
        #expect(decided.decide(text: "Без наказания", outcome: .noPenalty))
        stage.stewardIncidents = [incident, decided]
        let rows = StewardRole.watchIncidents(stage)
        #expect(rows.count == 1)
        #expect(rows.first?.driverNumbers == "007, 23")
        #expect(rows.first?.tasks.count == 1)
        #expect(rows.first?.tasks.first?.title == "Вынести решение")
        let roundTrip = try JSONDecoder().decode([WatchStewardIncident].self, from: JSONEncoder().encode(rows))
        #expect(roundTrip.first?.id == incident.incidentID)
        stage.myRole = Role(name: "Safety Car", shortName: "SC")
        #expect(StewardRole.watchIncidents(stage).isEmpty)
    }

    @Test func oldPhonePayloadStillDecodesWithoutIncidentFields() throws {
        let old = Data(#"{"championshipName":"Серия","seasonYear":2026,"stageName":"Этап","circuitName":"MRW","myRole":"SC","events":[]}"#.utf8)
        let schedule = try JSONDecoder().decode(WatchScheduleData.self, from: old)
        #expect(schedule.stewardMode == nil)
        #expect(schedule.stewardIncidents == nil)
        #expect(schedule.myRole == "SC")
    }

    @Test func mandatoryTasksDriveStateAndRequireVerdict() {
        let incident = StewardIncident(title: "Контакт в первом повороте", occurredAt: .now)
        incident.makeRequiredTasks()
        incident.makeRequiredTasks()
        #expect(incident.tasks.count == 2)
        #expect(incident.status == .submitted)
        #expect(!incident.decide(text: "Штраф 5 секунд", outcome: .penalty))
        incident.startReview()
        #expect(incident.status == .reviewing)
        #expect(incident.tasks.first(where: { $0.kind == "review" })?.completedAt != nil)
        #expect(!incident.decide(text: " \n ", outcome: .noPenalty))
        #expect(incident.status == .reviewing)
        #expect(incident.decide(text: "№7 — 5 секунд; №23 — без наказания", outcome: .penalty))
        #expect(incident.status == .decided)
        #expect(incident.tasks.first(where: { $0.kind == "decision" })?.completedAt != nil)
        incident.reopenReview()
        #expect(incident.status == .reviewing)
        #expect(!incident.verdict.isEmpty)
        #expect(incident.tasks.first(where: { $0.kind == "decision" })?.completedAt == nil)
    }

    @Test func extraTaskDoesNotChangeIncidentStatusOrDisappearAfterDecision() {
        let incident = StewardIncident(title: "Проверить видео", occurredAt: .now)
        incident.makeRequiredTasks()
        let extra = StewardIncidentTask(title: "Запросить бортовую камеру", incident: incident)
        incident.tasks.append(extra)
        extra.completedAt = .now
        #expect(incident.status == .submitted)
        extra.completedAt = nil
        incident.startReview()
        #expect(incident.decide(text: "Оснований для наказания нет", outcome: .noPenalty))
        #expect(incident.openTasks.contains(where: { $0 === extra }))
    }

    @Test func journalPersistsIndependentlyFromScheduleAndCascadesOnStageRemoval() throws {
        let container = try ModelContainer(for: Stage.self, StewardIncident.self, StewardIncidentTask.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now)
        context.insert(stage)
        let event = ScheduleEvent(title: "Гонка", plannedStart: .now, plannedDuration: 30, stage: stage)
        context.insert(event); stage.scheduleEvents.append(event)
        let incident = StewardIncident(title: "Контакт", occurredAt: .now, stage: stage)
        incident.driverNumbers = "007, 23"
        incident.makeRequiredTasks()
        context.insert(incident); stage.stewardIncidents.append(incident)
        try context.save()
        context.delete(event); stage.scheduleEvents.removeAll()
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<StewardIncident>()) == 1)
        #expect(incident.driverNumbers == "007, 23")
        #expect(try context.fetchCount(FetchDescriptor<StewardIncidentTask>()) == 2)
        context.delete(stage); try context.save()
        #expect(try context.fetchCount(FetchDescriptor<StewardIncident>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StewardIncidentTask>()) == 0)
    }

    @Test func roleGateDoesNotExposeJournalForSCOrAthlete() {
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now,
                          myRole: Role(name: "Спортивные комиссары", shortName: "КСК"))
        #expect(StewardRole.matches(stage))
        stage.participation = .athlete
        #expect(!StewardRole.matches(stage))
        stage.participation = .official
        stage.myRole = Role(name: "Safety Car", shortName: "SC")
        #expect(!StewardRole.matches(stage))
    }
}
