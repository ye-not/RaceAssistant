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
    /// Historical records with nil length remain unknown until explicitly corrected.
    var circuitLengthMetersSnapshot: Double?
    var configurationNameSnapshot: String?

    var distanceKilometers: Double? {
        guard let meters = circuitLengthMetersSnapshot, meters > 0 else { return nil }
        return Double(lapCount) * meters / 1000
    }

    func captureConfiguration(from event: ScheduleEvent) {
        circuitLengthMetersSnapshot = event.circuitLengthMeters
        configurationNameSnapshot = event.effectiveConfiguration?.name ?? event.stage?.circuit?.name
    }

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
        if let scheduleEvent { captureConfiguration(from: scheduleEvent) }
    }

    var isActive: Bool {
        isRunning ?? (startedAt != nil && endedAt == nil)
    }
}
