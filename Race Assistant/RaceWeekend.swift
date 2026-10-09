import Foundation
import SwiftData

/// A race meeting shared by one or more championship stages.
/// In build 1 the existing Stage.scheduleEvents relationship remains authoritative.
@Model
final class RaceWeekend {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var startDate: Date
    var endDate: Date
    var circuit: Circuit?

    @Relationship(deleteRule: .nullify, inverse: \Stage.raceWeekend)
    var stages: [Stage] = []

    init(
        name: String,
        startDate: Date,
        endDate: Date,
        circuit: Circuit? = nil
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.circuit = circuit
    }
}
