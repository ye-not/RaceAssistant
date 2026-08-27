import Foundation
import SwiftData

enum DefaultReferenceData {

    static func seedIfNeeded(
        modelContext: ModelContext
    ) {
        seedRoles(
            modelContext: modelContext
        )

        seedCircuits(
            modelContext: modelContext
        )

        seedRaceClasses(
            modelContext: modelContext
        )

        do {
            try modelContext.save()

            print(
                "Default reference data checked"
            )
        } catch {
            print(
                "Ошибка сохранения справочников: \(error)"
            )
        }
    }

    // MARK: - Roles

    private static func seedRoles(
        modelContext: ModelContext
    ) {
        let existingRoles =
            fetchRoles(
                modelContext: modelContext
            )

        let existingKeys =
            Set(
                existingRoles.map {
                    normalized(
                        $0.shortName.isEmpty
                            ? $0.name
                            : $0.shortName
                    )
                }
            )

        let defaults: [
            (
                name: String,
                shortName: String
            )
        ] = [
            (
                "Safety Car",
                "SC"
            ),
            (
                "Medical Car",
                "MC"
            ),
            (
                "Race Control",
                "RC"
            ),
            (
                "Pit Lane",
                "PL"
            ),
            (
                "Grid",
                "GRID"
            )
        ]

        for item in defaults {
            let key =
                normalized(
                    item.shortName
                )

            guard
                !existingKeys.contains(
                    key
                )
            else {
                continue
            }

            let role =
                Role(
                    name:
                        item.name,
                    shortName:
                        item.shortName,
                    active:
                        true
                )

            modelContext.insert(
                role
            )
        }
    }

    // MARK: - Circuits

    private static func seedCircuits(
        modelContext: ModelContext
    ) {
        let existingCircuits =
            fetchCircuits(
                modelContext: modelContext
            )

        let existingKeys =
            Set(
                existingCircuits.map {
                    normalized(
                        $0.name
                    )
                }
            )

        let defaults: [
            (
                name: String,
                city: String,
                country: String
            )
        ] = [
            (
                "Moscow Raceway",
                "Волоколамск",
                "Россия"
            ),
            (
                "Igora Drive",
                "Санкт-Петербург",
                "Россия"
            ),
            (
                "ADM Raceway",
                "Мячково",
                "Россия"
            ),
            (
                "KazanRing",
                "Казань",
                "Россия"
            ),
            (
                "Sochi Autodrom",
                "Сочи",
                "Россия"
            ),
            (
                "Smolensk Ring",
                "Смоленск",
                "Россия"
            ),
            (
                "Крепость Грозная",
                "Грозный",
                "Россия"
            ),
            (
                "NRing",
                "Нижний Новгород",
                "Россия"
            )
        ]

        for item in defaults {
            let key =
                normalized(
                    item.name
                )

            guard
                !existingKeys.contains(
                    key
                )
            else {
                continue
            }

            let circuit =
                Circuit(
                    name:
                        item.name,
                    city:
                        item.city,
                    country:
                        item.country
                )

            modelContext.insert(
                circuit
            )
        }
    }

    // MARK: - Race Classes

    private static func seedRaceClasses(
        modelContext: ModelContext
    ) {
        let existingClasses =
            fetchRaceClasses(
                modelContext: modelContext
            )

        let existingKeys =
            Set(
                existingClasses.map {
                    normalized(
                        $0.shortName.isEmpty
                            ? $0.name
                            : $0.shortName
                    )
                }
            )

        let defaults: [
            (
                name: String,
                shortName: String
            )
        ] = [
            (
                "GT3",
                "GT3"
            ),
            (
                "GT4",
                "GT4"
            ),
            (
                "Touring Car Racing",
                "TCR"
            ),
            (
                "Touring",
                "Touring"
            ),
            (
                "Super Production",
                "Super Production"
            ),
            (
                "S1600",
                "S1600"
            ),
            (
                "CN Prototype",
                "CN"
            ),
            (
                "Prototype",
                "Prototype"
            ),
            (
                "SMP F4",
                "F4"
            )
        ]

        for item in defaults {
            let key =
                normalized(
                    item.shortName
                )

            guard
                !existingKeys.contains(
                    key
                )
            else {
                continue
            }

            let raceClass =
                RaceClass(
                    name:
                        item.name,
                    shortName:
                        item.shortName,
                    active:
                        true
                )

            modelContext.insert(
                raceClass
            )
        }
    }

    // MARK: - Fetch

    private static func fetchRoles(
        modelContext: ModelContext
    ) -> [Role] {
        let descriptor =
            FetchDescriptor<Role>()

        do {
            return try modelContext.fetch(
                descriptor
            )
        } catch {
            print(
                "Ошибка чтения ролей: \(error)"
            )

            return []
        }
    }

    private static func fetchCircuits(
        modelContext: ModelContext
    ) -> [Circuit] {
        let descriptor =
            FetchDescriptor<Circuit>()

        do {
            return try modelContext.fetch(
                descriptor
            )
        } catch {
            print(
                "Ошибка чтения автодромов: \(error)"
            )

            return []
        }
    }

    private static func fetchRaceClasses(
        modelContext: ModelContext
    ) -> [RaceClass] {
        let descriptor =
            FetchDescriptor<RaceClass>()

        do {
            return try modelContext.fetch(
                descriptor
            )
        } catch {
            print(
                "Ошибка чтения классов: \(error)"
            )

            return []
        }
    }

    // MARK: - Helpers

    private static func normalized(
        _ value: String
    ) -> String {
        value
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
    }
}
