import Foundation
import SwiftData

@Model
final class Season {
    // Legacy field kept for compatibility with existing stores.
    var year: Int

    // New season identity/display fields.
    // Defaults are intentional so existing SwiftData stores can migrate additively.
    var name: String = ""
    var declaredStartYear: Int?
    var declaredEndYear: Int?

    var championship: Championship?

    @Relationship(deleteRule: .cascade, inverse: \Stage.season)
    var stages: [Stage] = []

    init(
        name: String,
        declaredStartYear: Int? = nil,
        declaredEndYear: Int? = nil,
        championship: Championship? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredYear = Int(trimmedName.prefix(4))

        self.name = trimmedName
        self.declaredStartYear = declaredStartYear
        self.declaredEndYear = declaredEndYear
        self.year = declaredStartYear ?? inferredYear ?? 0
        self.championship = championship
    }

    // Compatibility initializer for older call sites while migration is in progress.
    convenience init(
        year: Int,
        championship: Championship? = nil
    ) {
        self.init(
            name: String(year),
            declaredStartYear: year,
            declaredEndYear: year,
            championship: championship
        )
    }

    var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? String(year) : trimmedName
    }

    var actualStartYear: Int? {
        guard let firstDate = stages.map(\.startDate).min() else {
            return nil
        }
        return Calendar.current.component(.year, from: firstDate)
    }

    var actualEndYear: Int? {
        guard let lastDate = stages.map(\.endDate).max() else {
            return nil
        }
        return Calendar.current.component(.year, from: lastDate)
    }
}
