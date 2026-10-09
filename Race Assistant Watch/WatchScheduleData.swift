import Foundation

struct WatchStewardTask: Codable, Identifiable {
    let id: UUID
    let title: String
    let due: Date?
}

struct WatchStewardIncident: Codable, Identifiable {
    let id: UUID
    let title: String
    let occurredAt: Date
    let status: String
    let description: String
    let raceClass: String
    let driverNumbers: String
    let tasks: [WatchStewardTask]
}

struct WatchScheduleItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let start: Date
    let duration: Int
    let classes: [String]
    let roles: [String]

    // Optional keeps decoding compatible with a schedule payload
    // that was sent by the previous iPhone build.
    let isRace: Bool?
    var groupTitle: String? = nil

    let remind10Minutes: Bool
    let remind5Minutes: Bool
    let remind1Minute: Bool
}

struct WatchScheduleData: Codable {
    let championshipName: String
    let seasonYear: Int
    let stageName: String
    let circuitName: String
    let myRole: String
    let events: [WatchScheduleItem]
    var redFlagTitle: String? = nil
    var participationRawValue: String? = nil
    var stageAvailable: Bool? = nil
    var stewardMode: Bool? = nil
    var stewardIncidents: [WatchStewardIncident]? = nil
}

// Shared by the iPhone and Watch targets. All countdown rounding lives here.
enum RaceClock {
    static func countdown(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(date.timeIntervalSince(now))))
        if seconds <= 60 { return "\(seconds) сек" }
        if seconds <= 120 {
            let rounded = ((seconds + 9) / 10) * 10
            return "\(rounded / 60) мин \(String(format: "%02d", rounded % 60)) сек"
        }
        return duration(minutes: (seconds + 59) / 60)
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) ч" : "\(hours) ч \(remainder) мин"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = Calendar.current.component(.second, from: date) == 0
            ? "HH:mm" : "HH:mm:ss"
        return formatter.string(from: date)
    }
}
