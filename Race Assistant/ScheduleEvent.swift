import Foundation
import SwiftData

@Model
final class ScheduleEvent {
    var title: String
    var plannedStart: Date
    var plannedDuration: Int

    var actualStart: Date?
    var actualDuration: Int?

    var status: String
    // Тип активности
    var isRace: Bool = false
    var groupID: String?

    var stage: Stage?

    // Стабильный ID для уведомлений
    var notificationID: UUID = UUID()

    // Настройки напоминаний
    var remind10Minutes: Bool = true
    var remind5Minutes: Bool = true
    var remind1Minute: Bool = true

    @Relationship(
        deleteRule: .cascade,
        inverse: \EventRole.scheduleEvent
    )
    var eventRoles: [EventRole] = []

    @Relationship(
        deleteRule: .cascade,
        inverse: \EventClass.scheduleEvent
    )
    var eventClasses: [EventClass] = []
    
    @Relationship(
        deleteRule: .cascade,
        inverse: \SafetyCarPeriod.scheduleEvent
    )
    var safetyCarPeriods: [SafetyCarPeriod] = []

    init(
        title: String,
        plannedStart: Date,
        plannedDuration: Int,
        stage: Stage? = nil,
        isRace: Bool = false,
        groupID: String? = nil,
        remind10Minutes: Bool = true,
        remind5Minutes: Bool = true,
        remind1Minute: Bool = true,
    ) {
        self.title = title
        self.plannedStart = plannedStart
        self.plannedDuration = plannedDuration
        self.stage = stage
        self.groupID = groupID

        self.actualStart = nil
        self.actualDuration = nil
        self.status = "scheduled"
        self.isRace = isRace

        self.notificationID = UUID()

        self.remind10Minutes = remind10Minutes
        self.remind5Minutes = remind5Minutes
        self.remind1Minute = remind1Minute
    }
}
