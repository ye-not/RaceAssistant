import Foundation
import SwiftData

/// Local operational record. The original race and its Safety Car periods stay intact.
@Model
final class RaceInterruption {
    var raceID: UUID
    var flaggedAt: Date
    var originalPlannedStart: Date
    /// awaiting, ended, or resumed
    var outcomeRaw: String
    var fiveMinuteAt: Date?
    var continuationRaceID: UUID?
    /// Zero means the session was run by time, or distance has not been specified.
    var plannedLaps: Int
    var completedLaps: Int
    var continuationLaps: Int

    init(raceID: UUID, flaggedAt: Date, originalPlannedStart: Date, plannedLaps: Int = 0) {
        self.raceID = raceID
        self.flaggedAt = flaggedAt
        self.originalPlannedStart = originalPlannedStart
        self.outcomeRaw = "awaiting"
        self.plannedLaps = plannedLaps
        self.completedLaps = 0
        self.continuationLaps = 0
    }
}
