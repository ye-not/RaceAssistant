import Foundation
import SwiftData

@Model
final class Championship {
    var name: String
    var organizer: String

    @Relationship(deleteRule: .cascade, inverse: \Season.championship)
    var seasons: [Season] = []

    init(name: String, organizer: String = "") {
        self.name = name
        self.organizer = organizer
    }
}
