import Foundation

struct WatchScheduleItem: Codable, Identifiable {
    let id: UUID
    let title: String
    let start: Date
    let duration: Int
    let classes: [String]
    let roles: [String]

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
