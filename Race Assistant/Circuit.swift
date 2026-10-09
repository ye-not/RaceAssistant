import Foundation
import SwiftData

@Model
final class Circuit {
    var name: String
    var shortName: String = ""
    var city: String
    var country: String
    var lengthMeters: Double?
    var website: String = ""
    var circuitDescription: String = ""
    var latitude: Double?
    var longitude: Double?
    var coordinateNote: String = ""
    var sourceURL: String = ""
    @Attribute(.externalStorage) var logoData: Data?
    var defaultConfigurationID: UUID?
    var defaultConfiguration: CircuitConfiguration? {
        get { configurations.first { $0.configurationID == defaultConfigurationID && !$0.isArchived } }
        set { defaultConfigurationID = newValue?.configurationID }
    }
    @Relationship(deleteRule: .cascade, inverse: \CircuitConfiguration.circuit)
    var configurations: [CircuitConfiguration] = []

    var summary: String {
        let configuration = defaultConfiguration
        let length = configuration?.lengthMeters ?? lengthMeters
        return [name, configuration?.name, length.map { String(format: "%.3f км", $0 / 1000) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var hasCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

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
