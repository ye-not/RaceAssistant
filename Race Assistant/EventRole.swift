import Foundation
import SwiftData

@Model
final class EventRole {
    var scheduleEvent: ScheduleEvent?
    var role: Role?

    init(
        scheduleEvent: ScheduleEvent? = nil,
        role: Role? = nil
    ) {
        self.scheduleEvent = scheduleEvent
        self.role = role
    }
}
