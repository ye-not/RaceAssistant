import Foundation
import SwiftData

@Model
final class Circuit {
    var name: String
    var city: String
    var country: String

    init(
        name: String,
        city: String = "",
        country: String = ""
    ) {
        self.name = name
        self.city = city
        self.country = country
    }
}
