import Foundation
import SwiftData

@Model
final class Role {
    var name: String
    var shortName: String
    var active: Bool

    init(
        name: String,
        shortName: String = "",
        active: Bool = true
    ) {
        self.name = name
        self.shortName = shortName
        self.active = active
    }
}
