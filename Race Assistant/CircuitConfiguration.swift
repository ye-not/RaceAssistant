import Foundation
import SwiftData

@Model
final class CircuitConfiguration {
    var configurationID: UUID = UUID()
    var name: String
    var lengthMeters: Double?
    var isArchived: Bool = false
    @Attribute(.externalStorage) var schemeData: Data?
    var schemeMIMEType: String?
    var circuit: Circuit?

    init(name: String, lengthMeters: Double? = nil, circuit: Circuit? = nil) {
        self.name = name
        self.lengthMeters = lengthMeters
        self.circuit = circuit
    }
}

@MainActor
enum CircuitConfigurationSetup {
    static func seedMRW(_ context: ModelContext) {
        let key = "raceassistant.mrw.gp9.seed.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            let circuits = try context.fetch(FetchDescriptor<Circuit>())
            guard let circuit = circuits.first(where: {
                $0.name.caseInsensitiveCompare("Moscow Raceway") == .orderedSame ||
                $0.shortName.caseInsensitiveCompare("MRW") == .orderedSame
            }) else { return }
            let configuration: CircuitConfiguration
            if let existing = circuit.configurations.first(where: {
                $0.name.localizedCaseInsensitiveContains("GP9")
            }) {
                configuration = existing
            } else {
                configuration = CircuitConfiguration(name: "GP9 (DTM)", lengthMeters: 3931, circuit: circuit)
                context.insert(configuration)
                circuit.configurations.append(configuration)
                if let url = Bundle.main.url(forResource: "MRW_GP9", withExtension: "svg") {
                    configuration.schemeData = try Data(contentsOf: url)
                    configuration.schemeMIMEType = "image/svg+xml"
                }
            }
            if circuit.defaultConfiguration == nil, !configuration.isArchived {
                circuit.defaultConfiguration = configuration
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            context.rollback()
            print("Не удалось добавить MRW GP9: \(error)")
        }
    }
}

/// Known-distance subtotal. Never assign today's default to an old record.
enum SafetyCarDistance {
    static func text(_ periods: [SafetyCarPeriod]) -> String {
        let known = periods.compactMap(\.distanceKilometers)
        let total = known.reduce(0, +)
        let missing = periods.filter { $0.lapCount > 0 && $0.distanceKilometers == nil }.count
        if known.isEmpty { return missing > 0 ? "Длина не указана (\(missing) выездов)" : "0 км" }
        let value = String(format: "%.3f км", total)
        return missing == 0 ? value : "\(value) + \(missing) без длины"
    }
}
