import Foundation
import SwiftData
import UserNotifications

enum SeedDataImporter {

    private static let seedFileName =
        "RaceAssistantSeed"

    private static let seedFileExtension =
        "json"

    private static let importVersionKey =
        "RaceAssistantSeedImportVersion"

    // MARK: - Public

    static func importIfNeeded(
        modelContext: ModelContext
    ) {
        guard let seed = loadSeed() else {
            return
        }

        let importedVersion =
            UserDefaults.standard.integer(
                forKey: importVersionKey
            )

        guard importedVersion < seed.schemaVersion else {
            print(
                "Seed уже импортирован. Версия: \(importedVersion)"
            )
            return
        }

        do {
            try importSeed(
                seed,
                modelContext: modelContext
            )

            try modelContext.save()

            UserDefaults.standard.set(
                seed.schemaVersion,
                forKey: importVersionKey
            )

            print(
                "✅ Seed импортирован. Версия: \(seed.schemaVersion)"
            )

        } catch {
            print(
                "❌ Ошибка импорта Seed: \(error)"
            )
        }
    }

    @MainActor
    static func fillEmptyBundledSchedules(modelContext: ModelContext) {
        guard let seed = loadSeed() else { return }
        do {
            let existingClasses = try modelContext.fetch(FetchDescriptor<RaceClass>())
            try importRaceClasses(seed.referenceData.raceClasses.filter { item in
                !existingClasses.contains { normalized($0.shortName) == normalized(item.shortName) }
            }, modelContext: modelContext)
            for schedule in seed.scheduleImports {
                if try findStage(seriesName: schedule.seriesName, seasonName: schedule.seasonName,
                    seasonYear: schedule.seasonYear, stageName: schedule.stageName, modelContext: modelContext) == nil,
                   let series = seed.series.first(where: { normalized($0.name) == normalized(schedule.seriesName) }),
                   let seasonItem = series.seasons.first(where: {
                       (schedule.seasonName == nil || $0.resolvedName == schedule.seasonName)
                       && (schedule.seasonYear == nil || $0.resolvedLegacyYear == schedule.seasonYear)
                       && $0.stages.contains { normalized($0.name) == normalized(schedule.stageName) }
                   }),
                   let stageItem = seasonItem.stages.first(where: { normalized($0.name) == normalized(schedule.stageName) }) {
                    let championship = try findOrCreateChampionship(name: series.name, organizer: series.organizer, modelContext: modelContext)
                    let season = try findOrCreateSeason(item: seasonItem, championship: championship, modelContext: modelContext)
                    if try findCircuit(name: stageItem.circuitName, modelContext: modelContext) == nil,
                       let circuit = seed.referenceData.circuits.first(where: { normalized($0.name) == normalized(stageItem.circuitName) }) {
                        try importCircuits([circuit], modelContext: modelContext)
                    }
                    try findOrCreateStage(item: stageItem, season: season, modelContext: modelContext)
                }
                guard let stage = try findStage(seriesName: schedule.seriesName,
                    seasonName: schedule.seasonName, seasonYear: schedule.seasonYear,
                    stageName: schedule.stageName, modelContext: modelContext),
                    stage.scheduleEvents.isEmpty else { continue }
                try importSchedule(schedule, modelContext: modelContext)
            }
            try modelContext.save()
        } catch { modelContext.rollback(); print("Заполнение пустых расписаний: \(error)") }
    }

    // MARK: - Load JSON

    private static func loadSeed()
        -> RaceAssistantSeed? {

        guard let url =
            Bundle.main.url(
                forResource: seedFileName,
                withExtension:
                    seedFileExtension
            )
        else {
            print(
                "❌ RaceAssistantSeed.json не найден в Bundle"
            )

            return nil
        }

        do {
            let data =
                try Data(
                    contentsOf: url
                )

            let decoder =
                JSONDecoder()

            var seed = try decoder.decode(RaceAssistantSeed.self, from: data)
            for name in seed.scheduleFiles ?? [] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
                    throw ExternalScheduleError.invalidSchedule("Не найден файл \(name).json")
                }
                let file = try decoder.decode(ExternalScheduleFile.self, from: Data(contentsOf: url))
                seed.scheduleImports.append(contentsOf: file.scheduleImports.map { $0.asSeedScheduleImport })
            }
            return seed

        } catch {
            print(
                "❌ Ошибка чтения RaceAssistantSeed.json: \(error)"
            )

            return nil
        }
    }

    // MARK: - Main Import

    private static func importSeed(
        _ seed: RaceAssistantSeed,
        modelContext: ModelContext
    ) throws {

        try importRoles(
            seed.referenceData.roles,
            modelContext: modelContext
        )

        try importRaceClasses(
            seed.referenceData.raceClasses,
            modelContext: modelContext
        )

        try importCircuits(
            seed.referenceData.circuits,
            modelContext: modelContext
        )

        try normalizeLegacyCircuits(
            modelContext: modelContext
        )

        try importSeries(
            seed.series,
            modelContext: modelContext
        )

        try modelContext.save()

        for scheduleImport in seed.scheduleImports {
            try importSchedule(
                scheduleImport,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Roles

    private static func importRoles(
        _ items: [SeedRole],
        modelContext: ModelContext
    ) throws {

        let existing =
            try modelContext.fetch(
                FetchDescriptor<Role>()
            )

        for item in items {

            let alreadyExists =
                existing.contains { role in

                    normalized(
                        role.shortName
                    )
                    ==
                    normalized(
                        item.shortName
                    )

                    ||
                    
                    normalized(
                        role.name
                    )
                    ==
                    normalized(
                        item.name
                    )
                }

            guard !alreadyExists else {
                continue
            }

            let role =
                Role(
                    name:
                        item.name,
                    shortName:
                        item.shortName,
                    active:
                        item.active
                )

            modelContext.insert(
                role
            )
        }
    }

    // MARK: - Classes

    private static func importRaceClasses(
        _ items: [SeedRaceClass],
        modelContext: ModelContext
    ) throws {

        let existing =
            try modelContext.fetch(
                FetchDescriptor<RaceClass>()
            )

        for item in items {

            let alreadyExists =
                existing.contains { raceClass in

                    normalized(
                        raceClass.shortName
                    )
                    ==
                    normalized(
                        item.shortName
                    )

                    ||

                    normalized(
                        raceClass.name
                    )
                    ==
                    normalized(
                        item.name
                    )
                }

            guard !alreadyExists else {
                continue
            }

            let raceClass =
                RaceClass(
                    name:
                        item.name,
                    shortName:
                        item.shortName,
                    active:
                        item.active
                )

            modelContext.insert(
                raceClass
            )
        }
    }

    // MARK: - Circuits

    private static func importCircuits(
        _ items: [SeedCircuit],
        modelContext: ModelContext
    ) throws {

        let existing =
            try modelContext.fetch(
                FetchDescriptor<Circuit>()
            )

        for item in items {

            if let existingCircuit =
                existing.first(
                    where: {
                        normalized(
                            $0.name
                        )
                        ==
                        normalized(
                            item.name
                        )
                    }
                ) {

                existingCircuit.shortName =
                    item.shortName

                existingCircuit.city =
                    item.city

                existingCircuit.country =
                    item.country

                continue
            }

            let circuit =
                Circuit(
                    name:
                        item.name,
                    shortName:
                        item.shortName,
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

    // MARK: - Legacy circuit normalization

    private static func normalizeLegacyCircuits(
        modelContext: ModelContext
    ) throws {

        struct Rule {
            let canonicalName: String
            let city: String
            let country: String
            let aliases: [String]
        }

        let rules = [
            Rule(
                canonicalName: "KazanRing Canyon",
                city: "Казань",
                country: "Россия",
                aliases: [
                    "KazanRing"
                ]
            ),
            Rule(
                canonicalName: "NRing Circuit",
                city: "Нижний Новгород",
                country: "Россия",
                aliases: [
                    "NRing",
                    "Nring Curcuit",
                    "Nring Circuit"
                ]
            )
        ]

        var circuits = try modelContext.fetch(
            FetchDescriptor<Circuit>()
        )

        let stages = try modelContext.fetch(
            FetchDescriptor<Stage>()
        )

        for rule in rules {

            let acceptedNames = Set(
                ([rule.canonicalName] + rule.aliases)
                    .map { normalized($0) }
            )

            var matches = circuits.filter { circuit in
                acceptedNames.contains(
                    normalized(circuit.name)
                )
            }

            guard !matches.isEmpty else {
                continue
            }

            let canonical =
                matches.first(
                    where: {
                        normalized($0.name) ==
                        normalized(rule.canonicalName)
                    }
                )
                ?? matches[0]

            canonical.name = rule.canonicalName
            canonical.city = rule.city
            canonical.country = rule.country

            matches.removeAll { circuit in
                circuit === canonical
            }

            for duplicate in matches {

                for stage in stages {
                    if let stageCircuit = stage.circuit,
                       stageCircuit === duplicate {
                        stage.circuit = canonical
                    }
                }

                modelContext.delete(duplicate)
            }

            circuits = try modelContext.fetch(
                FetchDescriptor<Circuit>()
            )
        }
    }

    // MARK: - Championships / Seasons / Stages

    private static func importSeries(
        _ series: [SeedSeries],
        modelContext: ModelContext
    ) throws {

        for seriesItem in series {

            let championship =
                try findOrCreateChampionship(
                    name:
                        seriesItem.name,
                    organizer:
                        seriesItem.organizer,
                    modelContext:
                        modelContext
                )

            for seasonItem in
                seriesItem.seasons {

                let season =
                    try findOrCreateSeason(
                        item: seasonItem,
                        championship: championship,
                        modelContext: modelContext
                    )

                for stageItem in
                    seasonItem.stages {

                    try findOrCreateStage(
                        item:
                            stageItem,
                        season:
                            season,
                        modelContext:
                            modelContext
                    )
                }
            }
        }
    }

    // MARK: Championship

    private static func findOrCreateChampionship(
        name: String,
        organizer: String,
        modelContext: ModelContext
    ) throws -> Championship {

        let championships =
            try modelContext.fetch(
                FetchDescriptor<Championship>()
            )

        if let existing =
            championships.first(
                where: {
                    normalized(
                        $0.name
                    )
                    ==
                    normalized(
                        name
                    )
                }
            ) {

            // Не перетираем пользовательское значение,
            // если организатор уже заполнен.
            if existing.organizer
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty {

                existing.organizer =
                    organizer
            }

            return existing
        }

        let championship =
            Championship(
                name: name,
                organizer:
                    organizer
            )

        modelContext.insert(
            championship
        )

        return championship
    }

    // MARK: Season

    private static func findOrCreateSeason(
        item: SeedSeason,
        championship: Championship,
        modelContext: ModelContext
    ) throws -> Season {

        let seasonName = item.resolvedName
        let legacyYear = item.resolvedLegacyYear

        if let existing = championship.seasons.first(
            where: { season in
                normalized(season.displayName) == normalized(seasonName)
                || (legacyYear != nil && season.year == legacyYear)
            }
        ) {
            // Migrate old stored seasons forward without overwriting user-entered data.
            if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = seasonName
            }

            if existing.declaredStartYear == nil {
                existing.declaredStartYear = item.declaredStartYear ?? legacyYear
            }

            if existing.declaredEndYear == nil {
                existing.declaredEndYear = item.declaredEndYear ?? item.declaredStartYear ?? legacyYear
            }

            return existing
        }

        let season = Season(
            name: seasonName,
            declaredStartYear: item.declaredStartYear ?? legacyYear,
            declaredEndYear: item.declaredEndYear ?? item.declaredStartYear ?? legacyYear,
            championship: championship
        )

        modelContext.insert(season)
        championship.seasons.append(season)

        return season
    }

    // MARK: Stage

    @discardableResult
    private static func findOrCreateStage(
        item: SeedStage,
        season: Season,
        modelContext: ModelContext
    ) throws -> Stage {

        if let existing =
            season.stages.first(
                where: {
                    normalized(
                        $0.name
                    )
                    ==
                    normalized(
                        item.name
                    )
                }
            ) {

            // Намеренно НЕ переписываем даты,
            // если этап уже существует и пользователь
            // редактировал его вручную.

            if existing.circuit == nil {
                existing.circuit =
                    try findCircuit(
                        name:
                            item.circuitName,
                        modelContext:
                            modelContext
                    )
            }

            return existing
        }

        let startDate =
            try parseDate(
                item.startDate
            )

        let endDate =
            try parseDate(
                item.endDate
            )

        let circuit =
            try findCircuit(
                name:
                    item.circuitName,
                modelContext:
                    modelContext
            )

        let stage =
            Stage(
                name:
                    item.name,
                startDate:
                    startDate,
                endDate:
                    endDate,
                season:
                    season,
                circuit:
                    circuit
            )

        modelContext.insert(
            stage
        )

        season.stages.append(
            stage
        )

        return stage
    }

    // MARK: - Schedule

    private static func importSchedule(
        _ schedule: SeedScheduleImport,
        modelContext: ModelContext
    ) throws {

        guard let stage =
            try findStage(
                seriesName:
                    schedule.seriesName,
                seasonName:
                    schedule.seasonName,
                seasonYear:
                    schedule.seasonYear,
                stageName:
                    schedule.stageName,
                modelContext:
                    modelContext
            )
        else {
            print(
                "❌ Этап для расписания не найден: \(schedule.seriesName) / \(schedule.stageName)"
            )

            return
        }

        let allRoles =
            try modelContext.fetch(
                FetchDescriptor<Role>()
            )

        let allClasses =
            try modelContext.fetch(
                FetchDescriptor<RaceClass>()
            )

        var importedCount = 0
        var skippedCount = 0

        for item in schedule.events {

            guard let startTime =
                item.startTime
            else {
                // В исходном XLS есть несколько строк
                // без времени начала.
                // Для MVP их безопаснее пропустить,
                // чем выдумывать время.

                print(
                    "⚠️ Пропущена строка XLS \(item.sourceRow): нет времени начала — \(item.title)"
                )

                skippedCount += 1

                continue
            }

            let plannedStart =
                try combine(
                    dateString:
                        item.date,
                    timeString:
                        startTime,
                    timeZoneIdentifier: schedule.timeZoneIdentifier
                )
            let plannedDuration: Int

            if let endTime = item.endTime {

                let plannedEnd =
                    try combine(
                        dateString: item.date,
                        timeString: endTime,
                        timeZoneIdentifier: schedule.timeZoneIdentifier
                    )

                let calculatedDuration =
                    max(
                        0,
                        Int(
                            plannedEnd
                                .timeIntervalSince(plannedStart) / 60
                        )
                    )

                plannedDuration = calculatedDuration

                if calculatedDuration != item.durationMinutes {
                    print(
                        """
                        ⚠️ Schedule duration mismatch
                        Source row: \(item.sourceRow)
                        Event: \(item.title)
                        Date: \(item.date)
                        Time: \(startTime)–\(endTime)
                        XLS duration: \(item.durationMinutes) min
                        Calculated duration: \(calculatedDuration) min
                        Using calculated duration.
                        """
                    )
                }

            } else {

                plannedDuration = item.durationMinutes
            }
            // Защита от повторного импорта:
            // одна и та же строка определяется
            // названием + точным временем начала.

            let alreadyExists =
                stage.scheduleEvents
                    .contains { event in

                        normalized(
                            event.title
                        )
                        ==
                        normalized(
                            item.title
                        )

                        &&

                        abs(
                            event.plannedStart
                                .timeIntervalSince(
                                    plannedStart
                                )
                        ) < 1
                    }

            if alreadyExists {
                skippedCount += 1
                continue
            }

            let event =
                ScheduleEvent(
                    title:
                        item.title,
                    plannedStart:
                        plannedStart,
                    plannedDuration:
                        plannedDuration,
                    stage:
                        stage,
                    isRace:
                        item.isRace,
                    groupID:
                        item.groupID,
                    remind10Minutes:
                        item.remind10Minutes,
                    remind5Minutes:
                        item.remind5Minutes,
                    remind1Minute:
                        item.remind1Minute
                )

            modelContext.insert(
                event
            )

            stage.scheduleEvents.append(
                event
            )

            // MARK: Classes

            for shortName in
                item.classShortNames {

                guard let raceClass =
                    allClasses.first(
                        where: {
                            normalized(
                                $0.shortName
                            )
                            ==
                            normalized(
                                shortName
                            )
                        }
                    )
                else {
                    print(
                        "⚠️ Класс не найден: \(shortName), строка \(item.sourceRow)"
                    )

                    continue
                }

                let eventClass =
                    EventClass(
                        scheduleEvent:
                            event,
                        raceClass:
                            raceClass
                    )

                modelContext.insert(
                    eventClass
                )

                event.eventClasses.append(
                    eventClass
                )
            }

            // MARK: Roles

            for shortName in
                item.roleShortNames {

                guard let role =
                    allRoles.first(
                        where: {
                            normalized(
                                $0.shortName
                            )
                            ==
                            normalized(
                                shortName
                            )
                        }
                    )
                else {
                    print(
                        "⚠️ Роль не найдена: \(shortName), строка \(item.sourceRow)"
                    )

                    continue
                }

                let eventRole =
                    EventRole(
                        scheduleEvent:
                            event,
                        role:
                            role
                    )

                modelContext.insert(
                    eventRole
                )

                event.eventRoles.append(
                    eventRole
                )
            }

            importedCount += 1
        }

        print(
            "✅ Расписание импортировано: \(importedCount), пропущено: \(skippedCount)"
        )
    }

    // MARK: - Find Stage

    private static func findStage(
        seriesName: String,
        seasonName: String?,
        seasonYear: Int?,
        stageName: String,
        modelContext: ModelContext
    ) throws -> Stage? {

        let championships =
            try modelContext.fetch(
                FetchDescriptor<Championship>()
            )

        guard let championship =
            championships.first(
                where: {
                    normalized($0.name) ==
                    normalized(seriesName)
                }
            )
        else {
            return nil
        }

        let season = championship.seasons.first { candidate in
            if let seasonName,
               normalized(candidate.displayName) == normalized(seasonName) {
                return true
            }

            if let seasonYear, candidate.year == seasonYear {
                return true
            }

            return false
        }

        guard let season else {
            return nil
        }

        return season.stages.first(
            where: {
                normalized($0.name) ==
                normalized(stageName)
            }
        )
    }

    // MARK: - Find Circuit

    private static func findCircuit(
        name: String,
        modelContext: ModelContext
    ) throws -> Circuit? {

        let circuits =
            try modelContext.fetch(
                FetchDescriptor<Circuit>()
            )

        return circuits.first(
            where: {
                normalized(
                    $0.name
                )
                ==
                normalized(
                    name
                )
            }
        )
    }

    // MARK: - Date Helpers

    private static func parseDate(
        _ value: String
    ) throws -> Date {

        let formatter =
            DateFormatter()

        formatter.calendar =
            Calendar(
                identifier:
                    .gregorian
            )

        formatter.locale =
            Locale(
                identifier:
                    "en_US_POSIX"
            )

        formatter.timeZone =
            TimeZone.current

        formatter.dateFormat =
            "yyyy-MM-dd"

        guard let date =
            formatter.date(
                from: value
            )
        else {
            throw SeedImportError.invalidDate(
                value
            )
        }

        return date
    }

    private static func combine(
        dateString: String,
        timeString: String,
        timeZoneIdentifier: String? = nil
    ) throws -> Date {

        let formatter =
            DateFormatter()

        formatter.calendar =
            Calendar(
                identifier:
                    .gregorian
            )

        formatter.locale =
            Locale(
                identifier:
                    "en_US_POSIX"
            )

        if let identifier = timeZoneIdentifier {
            guard let zone = TimeZone(identifier: identifier) else {
                throw ExternalScheduleError.invalidSchedule("Неизвестный часовой пояс: \(identifier)")
            }
            formatter.timeZone = zone
        } else {
            formatter.timeZone = TimeZone.current
        }

        if timeString.count > 5 {
            formatter.dateFormat =
                "yyyy-MM-dd HH:mm:ss"
        } else {
            formatter.dateFormat =
                "yyyy-MM-dd HH:mm"
        }

        let value =
            "\(dateString) \(timeString)"

        guard let date =
            formatter.date(
                from: value
            )
        else {
            throw SeedImportError.invalidDate(
                value
            )
        }

        return date
    }

    // MARK: - Normalization

    private static func normalized(
        _ value: String
    ) -> String {

        value
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()
    }
}


// MARK: - JSON Models

private struct RaceAssistantSeed: Decodable {
    let schemaVersion: Int
    let generatedFrom: String
    

    let referenceData: SeedReferenceData

    let series: [SeedSeries]

    var scheduleImports: [SeedScheduleImport]
    let scheduleFiles: [String]?
}


private struct SeedReferenceData:
    Decodable {

    let roles:
        [SeedRole]

    let raceClasses:
        [SeedRaceClass]

    let circuits:
        [SeedCircuit]
}


private struct SeedRole:
    Decodable {

    let name: String
    let shortName: String
    let active: Bool
}


private struct SeedRaceClass:
    Decodable {

    let name: String
    let shortName: String
    let active: Bool
}


private struct SeedCircuit:
    Decodable {

    let name: String
    let shortName: String
    let city: String
    let country: String
    let lengthMeters: Int?
}


private struct SeedSeries:
    Decodable {

    let name: String
    let organizer: String
    let discipline: String

    let seasons:
        [SeedSeason]
}


private struct SeedSeason: Decodable {
    let name: String?
    let declaredStartYear: Int?
    let declaredEndYear: Int?
    let year: Int?
    let stages: [SeedStage]

    var resolvedName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        if let year {
            return String(year)
        }

        return "Сезон"
    }

    var resolvedLegacyYear: Int? {
        year ?? declaredStartYear
    }
}


private struct SeedStage:
    Decodable {

    let name: String
    let format: String
    let circuitName: String
    let startDate: String
    let endDate: String

    // Резервируем поле в формате seed уже сейчас.
    // В SwiftData начнём сохранять его после добавления
    // streamURL в модель Stage и UI.
    let streamURL: String?
}


private struct SeedScheduleImport: Decodable {
    let seriesName: String
    let seasonName: String?
    let seasonYear: Int?
    let stageName: String
    let timeZoneIdentifier: String?
    let events: [SeedScheduleEvent]
}


private struct SeedScheduleEvent:
    Decodable {

    let sourceRow: Int

    let date: String

    let startTime: String?
    let endTime: String?

    let durationMinutes: Int

    let title: String
    let type: String
    let isRace: Bool
    let groupID: String?

    let classShortNames:
        [String]

    let roleShortNames:
        [String]

    let sourceParticipantsText:
        String?

    let sourceOfficialsText:
        String?

    let remind10Minutes: Bool
    let remind5Minutes: Bool
    let remind1Minute: Bool
}


// MARK: - Errors

private enum SeedImportError:
    LocalizedError {

    case invalidDate(String)

    var errorDescription:
        String? {

        switch self {

        case .invalidDate(
            let value
        ):
            return
                "Некорректная дата: \(value)"
        }
    }
}

// MARK: - External JSON exchange

extension SeedDataImporter {

    struct ExternalImportResult {
        let stageCount: Int
        let eventCount: Int
    }

    /// Imports an operational JSON selected by the user.
    /// Only schedules explicitly present in `scheduleImports` are replaced.
    /// Stage settings (role, notification mode, reminder offsets) are preserved.
    @MainActor
    static func importExternalJSON(
        from url: URL,
        modelContext: ModelContext,
        expectedStage: Stage? = nil,
        updateReminders: Bool = true
    ) throws -> ExternalImportResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ExternalScheduleFile.self, from: data)
        if file.scheduleImports.isEmpty {
            throw ExternalScheduleError.invalidSchedule("Файл не содержит расписания")
        }
        var plans: [(schedule: ExternalScheduleImport, stage: Stage, protected: [(ScheduleEvent, Int)])] = []
        var seenStages = Set<PersistentIdentifier>()
        let storedSC = try modelContext.fetch(FetchDescriptor<SafetyCarPeriod>())
        // Validate the full batch BEFORE deleting any event or notification.
        for schedule in file.scheduleImports {
            guard let stage = try findStage(seriesName: schedule.seriesName,
                seasonName: schedule.seasonName, seasonYear: schedule.seasonYear,
                stageName: schedule.stageName, modelContext: modelContext) else {
                throw ExternalScheduleError.stageNotFound(schedule.stageName)
            }
            if let expectedStage, stage !== expectedStage {
                throw ExternalScheduleError.invalidSchedule("Выбран файл другого этапа: \(schedule.stageName)")
            }
            guard seenStages.insert(stage.persistentModelID).inserted else {
                throw ExternalScheduleError.invalidSchedule("Этап повторяется в файле: \(stage.name)")
            }
            var starts: [Date] = []
            var keys = Set<String>()
            for item in schedule.events {
                guard let time = item.startTime, item.durationMinutes >= 0 else {
                    throw ExternalScheduleError.invalidSchedule("Нет времени или неверная длительность: \(item.title)")
                }
                let start = try combine(dateString: item.date, timeString: time, timeZoneIdentifier: schedule.timeZoneIdentifier)
                starts.append(start)
                if let end = item.endTime { _ = try combine(dateString: item.date, timeString: end, timeZoneIdentifier: schedule.timeZoneIdentifier) }
                let key = "\(normalized(item.title))|\(start.timeIntervalSince1970)"
                guard keys.insert(key).inserted else {
                    throw ExternalScheduleError.invalidSchedule("Повтор события: \(item.title) · \(time)")
                }
            }
            var protected: [(ScheduleEvent, Int)] = []
            var usedIndexes = Set<Int>()
            for old in stage.scheduleEvents where storedSC.contains(where: { $0.scheduleEvent === old }) {
                let candidates = schedule.events.indices.filter { index in
                    let item = schedule.events[index]
                    guard item.isRace == old.isRace,
                          Calendar.current.isDate(starts[index], inSameDayAs: old.plannedStart) else { return false }
                    return normalized(item.title) == normalized(old.title) &&
                        Set(item.classShortNames) == Set(old.eventClasses.compactMap { $0.raceClass?.shortName })
                }
                let exact = candidates.filter { abs(starts[$0].timeIntervalSince(old.plannedStart)) < 1 }
                let matches = exact.isEmpty ? candidates : exact
                guard matches.count == 1, let index = matches.first, usedIndexes.insert(index).inserted else {
                    throw ExternalScheduleError.invalidSchedule(
                        "Гонка с записями SC не найдена однозначно в новом расписании: \(old.title). Импорт отменён, записи сохранены.")
                }
                protected.append((old, index))
            }
            plans.append((schedule, stage, protected))
        }
        try modelContext.save()
        var oldNotificationIDs: [UUID] = []
        do {
            if let refs = file.referenceData {
                try importRoles(refs.roles ?? [], modelContext: modelContext)
                try importRaceClasses(refs.raceClasses ?? [], modelContext: modelContext)
                try importCircuits(refs.circuits ?? [], modelContext: modelContext)
            }
            for plan in plans {
                let stage = plan.stage
                var preserved: [(Int, [SafetyCarPeriod], UUID, Date?, Int?, String)] = []
                for (event, index) in plan.protected {
                    let periods = storedSC.filter { $0.scheduleEvent === event }
                    preserved.append((index, periods, event.notificationID, event.actualStart, event.actualDuration, event.status))
                    event.safetyCarPeriods.removeAll()
                    for period in periods { period.scheduleEvent = nil }
                }
                let oldEvents = stage.scheduleEvents
                oldNotificationIDs.append(contentsOf: oldEvents.map { $0.notificationID })
                stage.scheduleEvents.removeAll()
                for event in oldEvents { modelContext.delete(event) }
                try importSchedule(plan.schedule.asSeedScheduleImport, modelContext: modelContext)
                for (index, periods, id, actualStart, actualDuration, status) in preserved {
                    let item = plan.schedule.events[index]
                    let start = try combine(dateString: item.date, timeString: item.startTime!, timeZoneIdentifier: plan.schedule.timeZoneIdentifier)
                    guard let replacement = stage.scheduleEvents.first(where: {
                        normalized($0.title) == normalized(item.title) && abs($0.plannedStart.timeIntervalSince(start)) < 1
                    }) else { throw ExternalScheduleError.invalidSchedule("Не удалось восстановить связь SC") }
                    replacement.notificationID = id
                    replacement.actualStart = actualStart
                    replacement.actualDuration = actualDuration
                    replacement.status = status
                    for period in periods { period.scheduleEvent = replacement }
                }
                stage.scheduleUpdatedAt = Date()
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        // Mutate notifications only after the database transaction succeeds.
        if updateReminders {
            let ids = oldNotificationIDs.flatMap { id in [10, 5, 1].map { "raceassistant-\(id.uuidString)-\($0)" } }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            Task { @MainActor in
                for plan in plans { await NotificationManager.shared.rescheduleNotifications(for: plan.stage) }
                PhoneWatchConnectivityManager.shared.sendPreferredStage()
            }
        }
        return ExternalImportResult(stageCount: plans.count,
                                    eventCount: plans.reduce(0) { $0 + $1.stage.scheduleEvents.count })
    }

    /// Exports the current stored schedules, not the bundled seed.
    static func exportCurrentJSON(modelContext: ModelContext, stage selectedStage: Stage? = nil) throws -> Data {
        let championships = try modelContext.fetch(FetchDescriptor<Championship>())
        let roles = try modelContext.fetch(FetchDescriptor<Role>())
        let classes = try modelContext.fetch(FetchDescriptor<RaceClass>())
        let circuits = try modelContext.fetch(FetchDescriptor<Circuit>())

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Calendar(identifier: .gregorian)
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone.current
        timeFormatter.dateFormat = "HH:mm:ss"

        func cleanTime(_ date: Date) -> String {
            let value = timeFormatter.string(from: date)
            return value.hasSuffix(":00") ? String(value.dropLast(3)) : value
        }

        var scheduleImports: [[String: Any]] = []

        for championship in championships.sorted(by: { $0.name < $1.name }) {
            for season in championship.seasons.sorted(by: { $0.displayName < $1.displayName }) {
                for stage in season.stages.sorted(by: { $0.startDate < $1.startDate }) {
                    if let selectedStage, stage !== selectedStage { continue }
                    let events = stage.scheduleEvents.sorted(by: { $0.plannedStart < $1.plannedStart })
                    guard !events.isEmpty || selectedStage != nil else { continue }

                    let eventJSON: [[String: Any]] = events.enumerated().map { index, event in
                        var object: [String: Any] = [
                            "sourceRow": index + 1,
                            "date": dateFormatter.string(from: event.plannedStart),
                            "startTime": cleanTime(event.plannedStart),
                            "durationMinutes": event.plannedDuration,
                            "title": event.title,
                            "type": event.isRace ? "race" : "schedule",
                            "isRace": event.isRace,
                            "classShortNames": event.eventClasses.compactMap { $0.raceClass?.shortName }.sorted(),
                            "roleShortNames": event.eventRoles.compactMap { $0.role?.shortName }.sorted(),
                            "remind10Minutes": event.remind10Minutes,
                            "remind5Minutes": event.remind5Minutes,
                            "remind1Minute": event.remind1Minute
                        ]

                        if let groupID = event.groupID { object["groupID"] = groupID }
                        else { object["groupID"] = NSNull() }

                        if event.plannedDuration > 0,
                           let end = Calendar.current.date(byAdding: .minute, value: event.plannedDuration, to: event.plannedStart) {
                            object["endTime"] = cleanTime(end)
                        } else {
                            object["endTime"] = NSNull()
                        }

                        object["sourceParticipantsText"] = NSNull()
                        object["sourceOfficialsText"] = NSNull()
                        return object
                    }

                    scheduleImports.append([
                        "seriesName": championship.name,
                        "seasonName": season.displayName,
                        "seasonYear": season.year,
                        "stageName": stage.name,
                "timeZoneIdentifier": TimeZone.current.identifier,
                        "events": eventJSON
                    ])
                }
            }
        }

        let root: [String: Any] = [
            "schemaVersion": 1,
            "generatedFrom": "Race Assistant export",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "referenceData": [
                "roles": roles.map { ["name": $0.name, "shortName": $0.shortName, "active": $0.active] },
                "raceClasses": classes.map { ["name": $0.name, "shortName": $0.shortName, "active": $0.active] },
                "circuits": circuits.map {
                    ["name": $0.name, "shortName": $0.shortName, "city": $0.city, "country": $0.country]
                }
            ],
            "scheduleImports": scheduleImports
        ]

        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

private struct ExternalScheduleFile: Decodable {
    let referenceData: ExternalReferenceData?
    let scheduleImports: [ExternalScheduleImport]
}

private struct ExternalReferenceData: Decodable {
    let roles: [SeedRole]?
    let raceClasses: [SeedRaceClass]?
    let circuits: [SeedCircuit]?
}

private struct ExternalScheduleImport: Decodable {
    let seriesName: String
    let seasonName: String?
    let seasonYear: Int?
    let stageName: String
    let timeZoneIdentifier: String?
    let events: [SeedScheduleEvent]

    var asSeedScheduleImport: SeedScheduleImport {
        SeedScheduleImport(
            seriesName: seriesName,
            seasonName: seasonName,
            seasonYear: seasonYear,
            stageName: stageName,
            timeZoneIdentifier: timeZoneIdentifier,
            events: events
        )
    }
}

private enum ExternalScheduleError: LocalizedError {
    case stageNotFound(String)
    case invalidSchedule(String)

    var errorDescription: String? {
        switch self {
        case .stageNotFound(let value):
            return "Этап не найден: \(value)"
        case .invalidSchedule(let value):
            return value
        }
    }
}
