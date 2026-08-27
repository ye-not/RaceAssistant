import Foundation
import SwiftData

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

            return try decoder.decode(
                RaceAssistantSeed.self,
                from: data
            )

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

        try importSeries(
            seed.series,
            modelContext: modelContext
        )

        try modelContext.save()

        try importSchedule(
            seed.scheduleImport,
            modelContext: modelContext
        )
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

            let alreadyExists =
                existing.contains { circuit in

                    normalized(
                        circuit.name
                    )
                    ==
                    normalized(
                        item.name
                    )
                }

            guard !alreadyExists else {
                continue
            }

            // Пока используем текущую модель Circuit:
            // name / city / country.
            //
            // shortName и lengthMeters из JSON
            // сохранять начнём после полевого теста.

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
                        year:
                            seasonItem.year,
                        championship:
                            championship,
                        modelContext:
                            modelContext
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
        year: Int,
        championship: Championship,
        modelContext: ModelContext
    ) throws -> Season {

        if let existing =
            championship.seasons.first(
                where: {
                    $0.year == year
                }
            ) {

            return existing
        }

        let season =
            Season(
                year: year,
                championship:
                    championship
            )

        modelContext.insert(
            season
        )

        championship.seasons.append(
            season
        )

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
                        startTime
                )

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
                        item.durationMinutes,
                    stage:
                        stage,
                    isRace:
                        item.isRace,
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
        seasonYear: Int,
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
                    normalized(
                        $0.name
                    )
                    ==
                    normalized(
                        seriesName
                    )
                }
            )
        else {
            return nil
        }

        guard let season =
            championship.seasons.first(
                where: {
                    $0.year ==
                    seasonYear
                }
            )
        else {
            return nil
        }

        return season.stages.first(
            where: {
                normalized(
                    $0.name
                )
                ==
                normalized(
                    stageName
                )
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
        timeString: String
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

private struct RaceAssistantSeed:
    Decodable {

    let schemaVersion: Int
    let generatedFrom: String

    let referenceData:
        SeedReferenceData

    let series:
        [SeedSeries]

    let scheduleImport:
        SeedScheduleImport
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


private struct SeedSeason:
    Decodable {

    let year: Int

    let stages:
        [SeedStage]
}


private struct SeedStage:
    Decodable {

    let name: String
    let format: String
    let circuitName: String
    let startDate: String
    let endDate: String
}


private struct SeedScheduleImport:
    Decodable {

    let seriesName: String
    let seasonYear: Int
    let stageName: String

    let events:
        [SeedScheduleEvent]
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
