import XCTest
import SwiftData
@testable import Race_Assistant

@MainActor
final class RaceWeekendFoundationTests: XCTestCase {
    func testTwoStagesCanShareWeekendWithoutMovingEvents() throws {
        let schema = Schema([RaceWeekend.self, Stage.self, ScheduleEvent.self,
                             Season.self, Championship.self, Circuit.self,
                             CircuitConfiguration.self, Role.self, RaceClass.self,
                             EventRole.self, EventClass.self, SafetyCarPeriod.self,
                             RaceInterruption.self, StewardIncident.self,
                             StewardIncidentTask.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(86_400)
        let weekend = RaceWeekend(name: "Joint meeting", startDate: start, endDate: end)
        let first = Stage(name: "Series A", startDate: start, endDate: end)
        let second = Stage(name: "Series B", startDate: start, endDate: end)
        let event = ScheduleEvent(title: "Race", plannedStart: start, plannedDuration: 30, stage: first)
        context.insert(weekend)
        context.insert(first)
        context.insert(second)
        context.insert(event)
        first.raceWeekend = weekend
        second.raceWeekend = weekend
        try context.save()
        XCTAssertEqual(weekend.stages.count, 2)
        XCTAssertEqual(first.scheduleEvents.count, 1)
        XCTAssertTrue(event.stage === first)
    }
}
