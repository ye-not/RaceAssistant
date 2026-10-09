import Foundation
import SwiftData

@Model
final class Championship {
    var name: String
    @Attribute(.externalStorage) var logoData: Data?
    var isFollowed: Bool = false
    var website: String = ""
    var organizer: String
    var raceClasses: [RaceClass] = []
    var classesConfigured: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Season.championship)
    var seasons: [Season] = []

    init(name: String, organizer: String = "") {
        self.name = name
        self.organizer = organizer
    }
}
