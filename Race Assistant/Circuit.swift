import Foundation
import SwiftData

@Model
final class Circuit {
    var name: String
    var shortName: String = ""
    var city: String
    var country: String

    init(
        name: String,
        shortName: String = "",
        city: String = "",
        country: String = ""
    ) {
        self.name = name
        self.shortName = shortName
        self.city = city
        self.country = country
    }
}
