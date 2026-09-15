import SwiftUI
import SwiftData

struct SafetyCarRecordRow: View {
    let period: SafetyCarPeriod
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(period.isActive ? "● SC активен" : "Выезд SC").fontWeight(.semibold)
                Spacer()
                Text("\(period.lapCount) кр.").monospacedDigit()
            }
            if let date = period.startedAt {
                Text("\(date.formatted(.dateTime.day().month())) · \(RaceClock.time(date))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !period.notes.isEmpty { Text(period.notes).font(.caption) }
        }.foregroundStyle(.primary)
    }
}

struct SafetyCarStatisticsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedPeriods: [SafetyCarPeriod]
    let stage: Stage
    var event: ScheduleEvent? = nil
    @State private var periodToEdit: SafetyCarPeriod?
    @State private var showingAdd = false
    @State private var errorMessage: String?

    private var periods: [SafetyCarPeriod] {
        storedPeriods.filter { period in
            period.scheduleEvent?.stage === stage && (event == nil || period.scheduleEvent === event)
        }
    }
    private var races: [ScheduleEvent] {
        stage.scheduleEvents.filter { $0.isRace && (event == nil || $0 === event) }
            .sorted { $0.plannedStart < $1.plannedStart }
    }
    private var classGroups: [String] { Array(Set(races.map { classTitle($0) })).sorted() }
    private func classTitle(_ event: ScheduleEvent) -> String {
        let value = SchedulePresentation.classes(event)
        return value.isEmpty ? "Без класса" : value
    }
    private func records(_ race: ScheduleEvent) -> [SafetyCarPeriod] {
        periods.filter { $0.scheduleEvent === race }.sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    var body: some View {
        List {
            Section(event == nil ? "Итого за этап" : "Итого за гонку") {
                LabeledContent("Выездов", value: "\(periods.count)")
                LabeledContent("Кругов под SC", value: "\(periods.reduce(0) { $0 + $1.lapCount })")
            }
            ForEach(classGroups, id: \.self) { group in
                let groupRaces = races.filter { classTitle($0) == group }
                let groupPeriods = groupRaces.flatMap { records($0) }
                Section("\(group) · \(groupPeriods.count) выездов · \(groupPeriods.reduce(0) { $0 + $1.lapCount }) кр.") {
                    ForEach(groupRaces) { race in
                        if event == nil {
                            NavigationLink {
                                SafetyCarStatisticsView(stage: stage, event: race)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(SchedulePresentation.raceLabel(race))
                                    let items = records(race)
                                    Text("\(items.count) выездов · \(items.reduce(0) { $0 + $1.lapCount }) кр.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        ForEach(records(race)) { period in
                            Button { periodToEdit = period } label: { SafetyCarRecordRow(period: period) }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("Удалить", role: .destructive) { delete(period) }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle(event == nil ? "SC · \(stage.name)" : "Выезды SC")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { EditSafetyCarPeriodView(stage: stage, selectedEvent: event) }
        .sheet(item: $periodToEdit) { EditSafetyCarPeriodView(stage: stage, period: $0) }
        .alert("Не удалось удалить", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }
    private func delete(_ period: SafetyCarPeriod) {
        modelContext.delete(period)
        do { try modelContext.save() }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
}

struct SafetyCarSeasonStatisticsView: View {
    @Query private var periods: [SafetyCarPeriod]
    let season: Season
    private var items: [SafetyCarPeriod] { periods.filter { $0.scheduleEvent?.stage?.season === season } }
    private var classes: [String] {
        Array(Set(items.compactMap { $0.scheduleEvent }.map { SchedulePresentation.classes($0) })).sorted()
    }
    var body: some View {
        List {
            Section("\(season.championship?.name ?? "") · \(season.displayName)") {
                LabeledContent("Выездов", value: "\(items.count)")
                LabeledContent("Кругов под SC", value: "\(items.reduce(0) { $0 + $1.lapCount })")
            }
            Section("По классам") {
                ForEach(classes, id: \.self) { name in
                    let selected = items.filter { $0.scheduleEvent.map { SchedulePresentation.classes($0) == name } ?? false }
                    LabeledContent(name.isEmpty ? "Без класса" : name,
                                   value: "\(selected.count) выездов · \(selected.reduce(0) { $0 + $1.lapCount }) кр.")
                }
                if items.isEmpty { Text("Выездов SC пока нет").foregroundStyle(.secondary) }
            }
            Section("Этапы") {
                ForEach(season.stages.sorted { $0.startDate < $1.startDate }) { stage in
                    let selected = items.filter { $0.scheduleEvent?.stage === stage }
                    NavigationLink { SafetyCarStatisticsView(stage: stage) } label: {
                        LabeledContent(stage.name, value: "\(selected.count) выездов · \(selected.reduce(0) { $0 + $1.lapCount }) кр.")
                    }
                }
            }
        }.navigationTitle("Статистика SC")
    }
}

struct SafetyCarAllSeasonsView: View {
    @Query private var seasons: [Season]
    @Query private var periods: [SafetyCarPeriod]
    var body: some View {
        List {
            ForEach(seasons.sorted { $0.year > $1.year }) { season in
                let items = periods.filter { $0.scheduleEvent?.stage?.season === season }
                NavigationLink { SafetyCarSeasonStatisticsView(season: season) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(season.championship?.name ?? "") · \(season.displayName)").font(.headline)
                        Text("\(items.count) выездов · \(items.reduce(0) { $0 + $1.lapCount }) кр.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("SC · сезоны")
    }
}
