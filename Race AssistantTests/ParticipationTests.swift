import Foundation
import Testing
@testable import Race_Assistant

@MainActor
struct ParticipationTests {
    @Test func legacyOfficialAndClassWithoutRole() {
        let sc = Role(name: "Safety Car", shortName: "SC")
        let stage = Stage(name: "Stage", startDate: .now, endDate: .now, myRole: sc)
        let value = RaceClass(name: "GT4", shortName: "GT4")
        let inspection = ScheduleEvent(title: "Medical inspection", plannedStart: .now, plannedDuration: 30, stage: stage)
        inspection.eventClasses = [EventClass(scheduleEvent: inspection, raceClass: value)]
        #expect(stage.participation == .official)
        #expect(stage.isInterested)
        #expect(!SchedulePresentation.relevant(inspection, stage: stage))
        inspection.eventRoles = [EventRole(scheduleEvent: inspection, role: sc)]
        #expect(SchedulePresentation.relevant(inspection, stage: stage))
    }

    @Test func athleteRequiresSelectedClassAndSpectatorIsExplicit() {
        let stage = Stage(name: "Stage", startDate: .now, endDate: .now)
        let gt4 = RaceClass(name: "GT4", shortName: "GT4")
        let tcr = RaceClass(name: "TCR", shortName: "TCR")
        let practice = ScheduleEvent(title: "Practice", plannedStart: .now, plannedDuration: 30, stage: stage)
        practice.eventClasses = [EventClass(scheduleEvent: practice, raceClass: gt4)]
        #expect(!stage.isInterested)
        stage.participation = .athlete
        #expect(stage.isInterested)
        #expect(!SchedulePresentation.relevant(practice, stage: stage))
        stage.participationClasses = [tcr]
        #expect(!SchedulePresentation.relevant(practice, stage: stage))
        stage.participationClasses = [gt4]
        #expect(SchedulePresentation.relevant(practice, stage: stage))
        stage.participation = .spectator
        #expect(SchedulePresentation.relevant(practice, stage: stage))
    }

    @Test func interestedStageBeforeEarlierUnselectedAndOrphansExcluded() {
        let championship = Championship(name: "Series")
        let season = Season(year: 2026, championship: championship)
        let now = Date()
        let early = Stage(name: "Early", startDate: now.addingTimeInterval(86400 * 2), endDate: now.addingTimeInterval(86400 * 2), season: season)
        let mine = Stage(name: "Mine", startDate: now.addingTimeInterval(86400 * 5), endDate: now.addingTimeInterval(86400 * 5), season: season)
        mine.participation = .spectator
        let deleted = Stage(name: "Orphan", startDate: now.addingTimeInterval(86400), endDate: now.addingTimeInterval(86400))
        let result = SchedulePresentation.upcoming([early, deleted, mine], now: now)
        #expect(result.count == 2)
        #expect(result.first === mine)
        #expect(result.last === early)
    }

    @Test func watchClearPayloadAndLegacyCompatibility() throws {
        var payload = WatchScheduleData(championshipName: "", seasonYear: 0, stageName: "", circuitName: "", myRole: "", events: [])
        payload.stageAvailable = false
        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(WatchScheduleData.self, from: data).stageAvailable == false)
        let old = WatchScheduleData(championshipName: "Series", seasonYear: 2026, stageName: "Stage", circuitName: "Circuit", myRole: "SC", events: [])
        let legacy = try JSONDecoder().decode(WatchScheduleData.self, from: JSONEncoder().encode(old))
        #expect(legacy.stageAvailable == nil)
        #expect(legacy.myRole == "SC")
    }
}
