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
            return "По моей роли"
        }
    }
}

@Model
final class Stage {
    var name: String
    var startDate: Date
    var endDate: Date

    var season: Season?
    var circuit: Circuit?

    // Последний внешний импорт расписания для этапа.
    var scheduleUpdatedAt: Date?

    // Роль пользователя на конкретном этапе
    var myRole: Role?

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
