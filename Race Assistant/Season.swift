import Foundation
import SwiftData

@Model
final class Season {
    var year: Int
    var championship: Championship?

    @Relationship(deleteRule: .cascade, inverse: \Stage.season)
    var stages: [Stage] = []

    init(year: Int, championship: Championship? = nil) {
        self.year = year
        self.championship = championship
    }
}
