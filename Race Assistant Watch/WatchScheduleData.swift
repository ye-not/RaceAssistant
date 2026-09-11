import Foundation

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
}
