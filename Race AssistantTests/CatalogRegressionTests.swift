import Foundation
import Testing
@testable import Race_Assistant

@MainActor
struct CatalogRegressionTests {
    @Test func oldEmptyStageClassSetIncludesOnlyClassesUsedByItsSchedule() {
        let used = RaceClass(name: "TCR")
        let unrelated = RaceClass(name: "GT4")
        let championship = Championship(name: "Серия")
        championship.raceClasses = [used, unrelated]
        let season = Season(year: 2026, championship: championship)
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now, season: season)
        stage.classesConfigured = true
        let event = ScheduleEvent(title: "Гонка", plannedStart: .now, plannedDuration: 30)
        event.eventClasses = [EventClass(raceClass: used), EventClass(raceClass: used)]
        stage.scheduleEvents = [event]
        #expect(stage.availableClasses.count == 1)
        #expect(stage.availableClasses.first === used)
        #expect(!stage.availableClasses.contains { $0 === unrelated })
    }

    @Test func ongoingStageRemainsInUpcomingAndFilters() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 14))!
        let championship = Championship(name: "РСКГ")
        let season = Season(year: 2026, championship: championship)
        let ongoing = Stage(name: "Сдвоенный этап", startDate: now.addingTimeInterval(-86400),
                            endDate: now.addingTimeInterval(86400 * 2), season: season)
        let ended = Stage(name: "Прошедший", startDate: now.addingTimeInterval(-86400 * 5),
                          endDate: now.addingTimeInterval(-86400 * 3), season: season)
        #expect(SchedulePresentation.upcoming([ended, ongoing], now: now).count == 1)
        #expect(SchedulePresentation.upcoming([ended, ongoing], now: now).first === ongoing)
    }

    @Test func stageClassSelectionDoesNotChangeWhenSeriesChanges() {
        let a = RaceClass(name: "GT4")
        let b = RaceClass(name: "TCR")
        let championship = Championship(name: "Серия")
        championship.raceClasses = [a]
        let season = Season(year: 2026, championship: championship)
        let stage = Stage(name: "Этап", startDate: .now, endDate: .now, season: season)
        #expect(stage.availableClasses.first === a)
        stage.raceClasses = [a]; stage.classesConfigured = true
        championship.raceClasses = [b]
        #expect(stage.availableClasses.first === a)
        #expect(stage.availableClasses.count == 1)
    }

    @Test func coordinatesAreOptionalAndValidated() {
        let circuit = Circuit(name: "Новая трасса")
        #expect(!circuit.hasCoordinates)
        circuit.latitude = 55; circuit.longitude = 37
        #expect(circuit.hasCoordinates)
        circuit.latitude = 100
        #expect(!circuit.hasCoordinates)
    }

    @Test func svgViewerRemovesFilterAndCrispEdgesWithoutChangingOriginal() {
        let source = #"<svg viewBox="0 0 10 10"><path filter="url(#shadow)" shape-rendering="crispEdges"/></svg>"#
        let data = Data(source.utf8)
        let cleaned = CircuitSchemeMarkup.svg(data)!
        #expect(!cleaned.contains("filter="))
        #expect(!cleaned.contains("crispEdges"))
        #expect(cleaned.contains("geometricPrecision"))
        #expect(String(data: data, encoding: .utf8) == source)
    }
}
