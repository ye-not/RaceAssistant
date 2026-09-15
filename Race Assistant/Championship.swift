import Foundation
import SwiftData

@Model
final class Championship {
    var name: String
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
