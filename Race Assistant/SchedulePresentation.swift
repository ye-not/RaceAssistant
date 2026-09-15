import Foundation
import SwiftData

@MainActor
enum SchedulePresentation {
    static func roleName(_ role: Role) -> String {
        role.shortName.isEmpty ? role.name : role.shortName
    }

    static func isSafetyCar(_ role: Role?) -> Bool {
        guard let role else { return false }
        return roleName(role).trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("SC") == .orderedSame
    }

    static func end(_ event: ScheduleEvent) -> Date {
        event.plannedStart.addingTimeInterval(TimeInterval(event.plannedDuration) * 60)
    }

    static func relevant(_ event: ScheduleEvent, role: Role?) -> Bool {
        guard let role else { return true }
        if isSafetyCar(role), event.isRace { return true }
        return event.eventRoles.contains { $0.role === role }
    }

    static func events(_ stage: Stage) -> [ScheduleEvent] {
        stage.scheduleEvents.filter {
            $0.status != "finished" && relevant($0, role: stage.myRole)
        }.sorted {
            if $0.plannedStart != $1.plannedStart { return $0.plannedStart < $1.plannedStart }
            return $0.notificationID.uuidString < $1.notificationID.uuidString
        }
    }

    static func current(_ events: [ScheduleEvent], now: Date) -> ScheduleEvent? {
        events.filter {
            $0.status != "finished" && $0.plannedDuration > 0 &&
            $0.plannedStart <= now && now < end($0)
        }.sorted {
            if $0.isRace != $1.isRace { return $0.isRace }
            return $0.plannedStart > $1.plannedStart
        }.first
    }

    static func todayStages(_ stages: [Stage], now: Date) -> [Stage] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return stages.filter {
            calendar.startOfDay(for: $0.startDate) <= today &&
            today <= calendar.startOfDay(for: $0.endDate)
        }.sorted {
            if ($0.myRole != nil) != ($1.myRole != nil) { return $0.myRole != nil }
            let lhs = distance($0, now: now), rhs = distance($1, now: now)
            if lhs != rhs { return lhs < rhs }
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.name < $1.name
        }
    }

    static func workingStage(_ stages: [Stage], now: Date) -> Stage? {
        todayStages(stages, now: now).first { $0.myRole != nil }
    }

    private static func distance(_ stage: Stage, now: Date) -> TimeInterval {
        let items = events(stage)
        if current(items, now: now) != nil { return 0 }
        return items.first { $0.plannedStart > now }?.plannedStart.timeIntervalSince(now)
            ?? .greatestFiniteMagnitude
    }

    static func groupTitle(_ event: ScheduleEvent) -> String? {
        guard let group = event.groupID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !group.isEmpty else { return nil }
        return group
    }

    static func classes(_ event: ScheduleEvent) -> String {
        event.eventClasses.compactMap { $0.raceClass }.map {
            $0.shortName.isEmpty ? $0.name : $0.shortName
        }.sorted().joined(separator: ", ")
    }

    static func raceLabel(_ event: ScheduleEvent, now: Date = .now) -> String {
        let start = event.actualStart ?? event.plannedStart
        let end = start.addingTimeInterval(TimeInterval(event.actualDuration ?? event.plannedDuration) * 60)
        let current = event.status != "finished" && start <= now && now < end
        let day = event.plannedStart.formatted(.dateTime.day().month())
        let name = classes(event)
        return "\(current ? "● СЕЙЧАС · " : "")\(name.isEmpty ? "Без класса" : name) · \(day) · \(RaceClock.time(event.plannedStart))"
    }
}
