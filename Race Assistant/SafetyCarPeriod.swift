import Foundation
import SwiftData

@Model
final class SafetyCarPeriod {
    var startedAt: Date?
    var endedAt: Date?
    // nil preserves the active state of pre-0.1.2 records during migration.
    var isRunning: Bool? = nil
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
        isRunning ?? (startedAt != nil && endedAt == nil)
    }
}
