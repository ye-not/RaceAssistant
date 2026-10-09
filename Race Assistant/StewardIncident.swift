import Foundation
import SwiftData

enum StewardIncidentStatus: String, CaseIterable {
    case submitted, reviewing, decided
    var title: String {
        switch self {
        case .submitted: return "Подан"
        case .reviewing: return "Рассматривается"
        case .decided: return "Решение вынесено"
        }
    }
}

enum StewardOutcome: String, CaseIterable, Identifiable {
    case noPenalty, penalty, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .noPenalty: return "Без наказания"
        case .penalty: return "Назначено наказание"
        case .other: return "Иное решение"
        }
    }
}

@Model
final class StewardIncident {
    var incidentID: UUID = UUID()
    var createdAt: Date = Date()
    var occurredAt: Date
    var title: String
    var incidentDescription: String = ""
    /// Free text preserves numbers such as 007 and identifiers containing letters.
    var driverNumbers: String = ""
    var raceClass: RaceClass?
    var stage: Stage?
    var verdict: String = ""
    var outcomeRaw: String = "noPenalty"
    var reviewStartedAt: Date?
    var decidedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \StewardIncidentTask.incident)
    var tasks: [StewardIncidentTask] = []

    var status: StewardIncidentStatus {
        if decidedAt != nil { return .decided }
        if reviewStartedAt != nil { return .reviewing }
        return .submitted
    }
    var outcome: StewardOutcome {
        get { StewardOutcome(rawValue: outcomeRaw) ?? .other }
        set { outcomeRaw = newValue.rawValue }
    }
    var openTasks: [StewardIncidentTask] { tasks.filter { $0.completedAt == nil } }

    init(title: String, occurredAt: Date, stage: Stage? = nil) {
        self.title = title
        self.occurredAt = occurredAt
        self.stage = stage
    }
    func makeRequiredTasks() {
        for kind in ["review", "decision"] where !tasks.contains(where: { $0.kind == kind }) {
            let task = StewardIncidentTask(title: kind == "review" ? "Взять в рассмотрение" : "Вынести решение", kind: kind)
            tasks.append(task)
            task.incident = self
        }
    }
    func startReview(at time: Date = .now) {
        guard status == .submitted else { return }
        makeRequiredTasks()
        reviewStartedAt = time
        tasks.first(where: { $0.kind == "review" })?.completedAt = time
    }
    /// Finishing the mandatory decision task cannot silently create an empty verdict.
    @discardableResult
    func decide(text: String, outcome: StewardOutcome, at time: Date = .now) -> Bool {
        guard status == .reviewing else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        verdict = trimmed
        self.outcome = outcome
        decidedAt = time
        tasks.first(where: { $0.kind == "decision" })?.completedAt = time
        return true
    }
    func reopenReview() {
        guard status == .decided else { return }
        decidedAt = nil
        tasks.first(where: { $0.kind == "decision" })?.completedAt = nil
        // Keep the previous verdict as a draft instead of discarding it.
    }
}

@Model
final class StewardIncidentTask {
    var taskID: UUID = UUID()
    var title: String
    var kind: String = "custom"
    var createdAt: Date = Date()
    var dueAt: Date?
    var completedAt: Date?
    var incident: StewardIncident?
    var isRequired: Bool { kind != "custom" }
    init(title: String, kind: String = "custom", incident: StewardIncident? = nil) {
        self.title = title
        self.kind = kind
        self.incident = incident
    }
}

enum StewardRole {
    @MainActor
    static func watchIncidents(_ stage: Stage) -> [WatchStewardIncident] {
        guard matches(stage) else { return [] }
        return stage.stewardIncidents.filter { $0.status != .decided }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.incidentID.uuidString < $1.incidentID.uuidString
            }
            .map { incident in
                WatchStewardIncident(
                    id: incident.incidentID, title: incident.title,
                    occurredAt: incident.occurredAt, status: incident.status.title,
                    description: incident.incidentDescription,
                    raceClass: incident.raceClass.map { $0.shortName.isEmpty ? $0.name : $0.shortName } ?? "",
                    driverNumbers: incident.driverNumbers,
                    tasks: incident.openTasks.sorted {
                        if $0.dueAt != $1.dueAt { return ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                        return $0.createdAt < $1.createdAt
                    }.map { WatchStewardTask(id: $0.taskID, title: $0.title, due: $0.dueAt) }
                )
            }
    }

    static func matches(_ stage: Stage) -> Bool {
        guard stage.participation == .official, let role = stage.myRole else { return false }
        let code = role.shortName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = role.name.lowercased()
        return ["КСК", "KSK", "ST", "STEWARD", "STEWARDS"].contains(code) ||
            name.contains("спортивн") && name.contains("комиссар") ||
            name.contains("стюард") || name.contains("стюарт") || name.contains("steward")
    }
}
