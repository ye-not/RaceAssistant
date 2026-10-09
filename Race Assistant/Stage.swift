import Foundation
import SwiftData

enum StageNotificationMode: String, Codable, CaseIterable {
    case none
    case all
    case myRole

    var title: String {
        switch self {
        case .none:
            return "Не уведомлять"

        case .all:
            return "Все события"

        case .myRole:
            return "По моему участию"
        }
    }
}

@Model
final class Stage {
    var name: String
    var startDate: Date
    var endDate: Date

    /// Optional until the existing store has been safely migrated.
    var raceWeekend: RaceWeekend?

    var season: Season?
    var circuit: Circuit?
    /// nil inherits the circuit default; does not copy it into every race.
    var circuitConfiguration: CircuitConfiguration?

    var effectiveConfiguration: CircuitConfiguration? {
        if let chosen = circuitConfiguration, chosen.circuit === circuit { return chosen }
        return circuit?.defaultConfiguration
    }

    // Последний внешний импорт расписания для этапа.
    var scheduleUpdatedAt: Date?

    // Роль пользователя на конкретном этапе
    var myRole: Role?

    var participationRawValue: String = "unspecified"
    var participationClasses: [RaceClass] = []
    var raceClasses: [RaceClass] = []
    var classesConfigured: Bool = false
    var availableClasses: [RaceClass] {
        let used = scheduleEvents.flatMap(\.eventClasses).compactMap(\.raceClass)
        let configured = classesConfigured ? raceClasses :
            (used.isEmpty ? (season?.championship?.raceClasses ?? []) : raceClasses)
        var seen = Set<PersistentIdentifier>()
        return (configured + used).filter { seen.insert($0.persistentModelID).inserted }
    }
    var scheduleTimeZoneIdentifier: String?

    var participation: StageParticipation {
        get {
            // Existing role assignments migrate without changing the stored relationship.
            if participationRawValue == "unspecified", myRole != nil { return .official }
            return StageParticipation(rawValue: participationRawValue) ?? .unspecified
        }
        set { participationRawValue = newValue.rawValue }
    }

    var isInterested: Bool { participation != .unspecified }
    var participationTitle: String {
        if participation == .official, let role = myRole {
            return "Официальное лицо · \(role.shortName.isEmpty ? role.name : role.shortName)"
        }
        if participation == .athlete, !participationClasses.isEmpty {
            return "Спортсмен · " + participationClasses.map { $0.shortName.isEmpty ? $0.name : $0.shortName }.sorted().joined(separator: ", ")
        }
        return participation.title
    }

    // MARK: - Notification Settings

    // Храним String, а не enum напрямую,
    // чтобы SwiftData было проще мигрировать.

    var notificationModeRawValue: String = "none"

    var stageRemind10Minutes: Bool = false
    var stageRemind5Minutes: Bool = false
    var stageRemind1Minute: Bool = false

    var notificationMode: StageNotificationMode {
        get {
            StageNotificationMode(
                rawValue: notificationModeRawValue
            ) ?? .none
        }

        set {
            notificationModeRawValue =
                newValue.rawValue
        }
    }

    @Relationship(
        deleteRule: .cascade,
        inverse: \ScheduleEvent.stage
    )
    var scheduleEvents: [ScheduleEvent] = []

    @Relationship(deleteRule: .cascade, inverse: \StewardIncident.stage)
    var stewardIncidents: [StewardIncident] = []

    init(
        name: String,
        startDate: Date,
        endDate: Date,
        season: Season? = nil,
        circuit: Circuit? = nil,
        myRole: Role? = nil,
        notificationMode: StageNotificationMode = .none,
        stageRemind10Minutes: Bool = false,
        stageRemind5Minutes: Bool = false,
        stageRemind1Minute: Bool = false
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.season = season
        self.circuit = circuit
        self.scheduleUpdatedAt = nil
        self.myRole = myRole

        self.notificationModeRawValue =
            notificationMode.rawValue

        self.stageRemind10Minutes =
            stageRemind10Minutes

        self.stageRemind5Minutes =
            stageRemind5Minutes

        self.stageRemind1Minute =
            stageRemind1Minute
    }
}
