import Foundation
import SwiftData
import Testing
@testable import Race_Assistant

@MainActor
struct Race_AssistantTests {
    @Test func countdownBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cases: [(Double, String)] = [
            (300, "5 мин"), (299, "5 мин"), (241, "5 мин"),
            (121, "3 мин"), (120, "2 мин 00 сек"), (116, "2 мин 00 сек"),
            (110, "1 мин 50 сек"), (106, "1 мин 50 сек"), (70, "1 мин 10 сек"),
            (61, "1 мин 10 сек"), (60, "60 сек"), (59, "59 сек"),
            (58, "58 сек"), (1, "1 сек"), (0, "0 сек"), (-1, "0 сек")
        ]
        for (remaining, expected) in cases {
            #expect(RaceClock.countdown(until: now.addingTimeInterval(remaining), now: now) == expected)
        }
    }

    @Test func secondsAreSortedAndDisplayed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let a = ScheduleEvent(title: "Минута", plannedStart: start, plannedDuration: 0)
        let b = ScheduleEvent(title: "15 секунд", plannedStart: start.addingTimeInterval(45), plannedDuration: 0)
        let stage = Stage(name: "Тест", startDate: start, endDate: start)
        stage.scheduleEvents = [b, a]
        #expect(SchedulePresentation.events(stage).map(\.title) == ["Минута", "15 секунд"])
        #expect(RaceClock.time(a.plannedStart).count == 5)
        #expect(RaceClock.time(b.plannedStart).hasSuffix(":45"))
    }

    @Test func workingStageAndRaceTakePriority() {
        let now = Date()
        let sc = Role(name: "Safety Car", shortName: "SC")
        let stage = Stage(name: "РСКГ", startDate: now, endDate: now, myRole: sc)
        let spectator = Stage(name: "F1", startDate: now, endDate: now)
        let race = ScheduleEvent(title: "Гонка", plannedStart: now.addingTimeInterval(-60), plannedDuration: 30, stage: stage, isRace: true)
        stage.scheduleEvents = [race]
        #expect(SchedulePresentation.todayStages([spectator, stage], now: now).count == 2)
        #expect(SchedulePresentation.workingStage([spectator, stage], now: now) === stage)
        #expect(SchedulePresentation.events(stage).contains { $0 === race })
        let medical = ScheduleEvent(title: "Медосмотр", plannedStart: now.addingTimeInterval(-3600), plannedDuration: 600)
        #expect(SchedulePresentation.current([medical, race], now: now) === race)
        race.status = "finished"
        #expect(SchedulePresentation.current([race], now: now) == nil)
    }

    @Test func manualSCIsNotLiveAndLegacyStateSurvives() {
        let period = SafetyCarPeriod(startedAt: .now)
        #expect(period.isActive)
        period.isRunning = false
        #expect(!period.isActive)
        let oldFinished = SafetyCarPeriod(startedAt: .now, endedAt: .now)
        #expect(!oldFinished.isActive)
    }

    @Test func deletionUpdatesPersistedTotals() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now)
        let race = ScheduleEvent(title: "Гонка", plannedStart: .now, plannedDuration: 30, stage: stage, isRace: true)
        context.insert(stage); context.insert(race)
        let period = SafetyCarPeriod(startedAt: .now, lapCount: 3, scheduleEvent: race)
        context.insert(period)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SafetyCarPeriod>()).count == 1)
        context.delete(period)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SafetyCarPeriod>()).isEmpty)
    }

    @Test func scheduleRoundTripPreservesSCAndRole() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let championship = Championship(name: "Test Series")
        let season = Season(year: 2026, championship: championship)
        let sc = Role(name: "Safety Car", shortName: "SC")
        let stage = Stage(name: "Test Stage", startDate: .now, endDate: .now, season: season, myRole: sc)
        context.insert(championship); context.insert(season); context.insert(sc); context.insert(stage)
        let race = ScheduleEvent(title: "Гонка", plannedStart: Date(timeIntervalSince1970: 1_800_000_000), plannedDuration: 30, stage: stage, isRace: true)
        context.insert(race)
        let period = SafetyCarPeriod(startedAt: race.plannedStart, lapCount: 3, notes: "Тест", scheduleEvent: race)
        period.isRunning = false
        context.insert(period)
        try context.save()
        let data = try SeedDataImporter.exportCurrentJSON(modelContext: context, stage: stage)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        _ = try SeedDataImporter.importExternalJSON(from: url, modelContext: context, expectedStage: stage, updateReminders: false)
        let saved = try context.fetch(FetchDescriptor<SafetyCarPeriod>())
        #expect(saved.count == 1)
        #expect(saved.first?.lapCount == 3)
        #expect(saved.first?.notes == "Тест")
        #expect(saved.first?.scheduleEvent?.stage === stage)
        #expect(stage.myRole === sc)
        #expect(stage.scheduleEvents.count == 1)
        #expect(saved.first?.isActive == false)

        // Removing a protected race from an update must fail without deleting its SC records.
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var schedules = try #require(object["scheduleImports"] as? [[String: Any]])
        schedules[0]["events"] = []
        object["scheduleImports"] = schedules
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        var rejected = false
        do {
            _ = try SeedDataImporter.importExternalJSON(from: url, modelContext: context, expectedStage: stage, updateReminders: false)
        } catch { rejected = true }
        #expect(rejected)
        #expect(try context.fetch(FetchDescriptor<SafetyCarPeriod>()).count == 1)
        #expect(stage.scheduleEvents.count == 1)
    }

    @Test func classSetupPreservesExplicitEmptySelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let championship = Championship(name: "Test")
        let season = Season(year: 2026, championship: championship)
        let stage = Stage(name: "Stage", startDate: .now, endDate: .now, season: season)
        let race = ScheduleEvent(title: "Race", plannedStart: .now, plannedDuration: 30, stage: stage, isRace: true)
        let raceClass = RaceClass(name: "Test class", shortName: "TC")
        context.insert(championship); context.insert(season); context.insert(stage)
        context.insert(race); context.insert(raceClass)
        context.insert(EventClass(scheduleEvent: race, raceClass: raceClass))
        try context.save()
        ChampionshipClassSetup.configure(context)
        #expect(championship.raceClasses.contains { $0 === raceClass })
        championship.raceClasses = []
        championship.classesConfigured = true
        try context.save()
        ChampionshipClassSetup.configure(context)
        #expect(championship.raceClasses.isEmpty)
        #expect(race.eventClasses.count == 1)
    }

    @Test func explicitSourceTimeZoneIsRespected() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let championship = Championship(name: "Zone Series")
        let season = Season(year: 2026, championship: championship)
        let stage = Stage(name: "Zone Stage", startDate: .now, endDate: .now, season: season)
        context.insert(championship); context.insert(season); context.insert(stage)
        let race = ScheduleEvent(title: "Race", plannedStart: .now, plannedDuration: 30, stage: stage, isRace: true)
        context.insert(race)
        try context.save()
        let data = try SeedDataImporter.exportCurrentJSON(modelContext: context, stage: stage)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var schedules = try #require(object["scheduleImports"] as? [[String: Any]])
        var events = try #require(schedules[0]["events"] as? [[String: Any]])
        events[0]["date"] = "2026-09-26"
        events[0]["startTime"] = "14:00"
        events[0]["endTime"] = "16:00"
        events[0]["durationMinutes"] = 120
        schedules[0]["events"] = events
        schedules[0]["timeZoneIdentifier"] = "Europe/Moscow"
        object["scheduleImports"] = schedules
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        _ = try SeedDataImporter.importExternalJSON(from: url, modelContext: context, expectedStage: stage, updateReminders: false)
        let expected = ISO8601DateFormatter().date(from: "2026-09-26T11:00:00Z")
        #expect(stage.scheduleEvents.first?.plannedStart == expected)
        #expect(stage.scheduleEvents.first?.plannedDuration == 120)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Championship.self, Season.self, Stage.self, ScheduleEvent.self,
            Circuit.self, Role.self, RaceClass.self, EventRole.self, EventClass.self, SafetyCarPeriod.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
}
