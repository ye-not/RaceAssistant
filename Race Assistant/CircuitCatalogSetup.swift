import Foundation
import SwiftData
import UIKit

@MainActor
enum CircuitCatalogSetup {
    private struct Catalog: Decodable {
        let version: Int
        let circuits: [Entry]
        let series: [SeriesEntry]
    }
    private struct Entry: Decodable {
        let name: String
        let shortName: String
        let lengthMeters: Double
        let previousLengthMeters: Double?
        let website: String
        let description: String
        let sourceURL: String
        let logoAsset: String?
        let latitude: Double?
        let longitude: Double?
        let coordinateNote: String
    }
    private struct SeriesEntry: Decodable {
        let name: String
        let website: String
        let logoAsset: String?
    }
    static func apply(_ context: ModelContext) {
        let key = "raceassistant.circuitCatalog.version"
        guard let url = Bundle.main.url(forResource: "CircuitCatalog", withExtension: "json"),
              let bytes = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: bytes),
              UserDefaults.standard.integer(forKey: key) < catalog.version else { return }
        do {
            let circuits = try context.fetch(FetchDescriptor<Circuit>())
            for entry in catalog.circuits {
                guard let circuit = circuits.first(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) else { continue }
                // Only update the shipped baseline; preserve user-entered length and other fields.
                if circuit.lengthMeters == nil || circuit.lengthMeters == entry.previousLengthMeters { circuit.lengthMeters = entry.lengthMeters }
                if circuit.website.isEmpty { circuit.website = entry.website }
                if circuit.circuitDescription.isEmpty { circuit.circuitDescription = entry.description }
                if circuit.sourceURL.isEmpty { circuit.sourceURL = entry.sourceURL }
                if circuit.logoData == nil, let name = entry.logoAsset { circuit.logoData = UIImage(named: name)?.pngData() }
                if circuit.latitude == nil && circuit.longitude == nil {
                    circuit.latitude = entry.latitude; circuit.longitude = entry.longitude; circuit.coordinateNote = entry.coordinateNote
                }
            }
            let championships = try context.fetch(FetchDescriptor<Championship>())
            for entry in catalog.series {
                guard let series = championships.first(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) else { continue }
                if series.logoData == nil, let name = entry.logoAsset { series.logoData = UIImage(named: name)?.pngData() }
                if series.website.isEmpty { series.website = entry.website }
            }
            try context.save()
            UserDefaults.standard.set(catalog.version, forKey: key)
        } catch { context.rollback(); print("Справочник автодромов: \(error)") }
    }
}
