import Foundation
import SwiftData

@Model
final class SafetyCarPeriod {
    var startedAt: Date?
    var endedAt: Date?
    var lapCount: Int
    var notes: String

    var scheduleEvent: ScheduleEvent?

    init(
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        lapCount: Int = 0,
        notes: String = "",
        scheduleEvent: ScheduleEvent? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lapCount = lapCount
        self.notes = notes
        self.scheduleEvent = scheduleEvent
    }

    var isActive: Bool {
        startedAt != nil && endedAt == nil
    }
}
