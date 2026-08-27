import Foundation
import SwiftData

@Model
final class EventClass {
    var scheduleEvent: ScheduleEvent?
    var raceClass: RaceClass?

    init(
        scheduleEvent: ScheduleEvent? = nil,
        raceClass: RaceClass? = nil
    ) {
        self.scheduleEvent = scheduleEvent
        self.raceClass = raceClass
    }
}
