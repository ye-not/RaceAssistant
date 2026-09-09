import SwiftUI
import SwiftData

struct ChampionshipDetailView: View {
    let championship: Championship

    @State private var showingAddSeason = false
    @State private var seasonForNewStage: Season?
    @State private var stageToOpen: Stage?

    @State private var expandedSeasonIDs: Set<PersistentIdentifier> = []
    @State private var didConfigureInitialExpansion = false

    var body: some View {
        List {
            if championship.seasons.isEmpty {
                ContentUnavailableView(
                    "Нет сезонов",
                    systemImage: "calendar",
                    description: Text("Добавь первый сезон")
                )
            } else {
                ForEach(sortedSeasons) { season in
                    seasonSection(season)
                }
            }
        }
        .navigationTitle(championship.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSeason = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSeason) {
            AddSeasonView(championship: championship) { season in
                expandedSeasonIDs.insert(season.persistentModelID)
            }
        }
        .sheet(item: $seasonForNewStage) { season in
            AddStageView(season: season) { stage in
                expandedSeasonIDs.insert(season.persistentModelID)
                stageToOpen = stage
            }
        }
        .navigationDestination(item: $stageToOpen) { stage in
            StageDetailView(stage: stage)
        }
        .onAppear {
            configureInitialExpansion()
        }
    }

    private var sortedSeasons: [Season] {
        championship.seasons.sorted {
            seasonSortDate($0) > seasonSortDate($1)
        }
    }

    private func seasonSortDate(_ season: Season) -> Date {
        if let firstStage = season.stages.map(\.startDate).min() {
            return firstStage
        }

        let year = season.declaredStartYear ?? season.year

        return Calendar.current.date(
            from: DateComponents(year: year, month: 1, day: 1)
        ) ?? .distantPast
    }

    @ViewBuilder
    private func seasonSection(_ season: Season) -> some View {
        let expanded =
            expandedSeasonIDs.contains(season.persistentModelID)

        Section {
            if expanded {
                if season.stages.isEmpty {
                    Text("Нет этапов")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedStages(for: season)) { stage in
                        NavigationLink {
                            StageDetailView(stage: stage)
                        } label: {
                            stageRow(stage)
                        }
                    }
                }

                Button {
                    seasonForNewStage = season
                } label: {
                    Label("Добавить этап", systemImage: "plus")
                }
            }
        } header: {
            Button {
                toggleSeason(season)
            } label: {
                HStack(spacing: 10) {
                    Image(
                        systemName: expanded
                            ? "chevron.down"
                            : "chevron.right"
                    )
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)

                    Text(season.displayName)
                        .font(.headline)

                    Spacer()

                    Text(stagesCountText(season.stages.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func stageRow(_ stage: Stage) -> some View {
        let state = stageState(stage)

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if state == .current {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)

                        Text("СЕЙЧАС")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }

                    Text(stage.name)
                        .font(.headline)
                        .foregroundStyle(
                            state == .past
                                ? Color.secondary
                                : Color.primary
                        )
                }

                HStack(spacing: 6) {
                    Text(stageDateText(stage))

                    if let circuit = stage.circuit {
                        Text("·")
                        Text(
                            circuit.shortName.isEmpty
                                ? circuit.name
                                : circuit.shortName
                        )
                    }
                }
                .font(.subheadline)
                .foregroundStyle(
                    state == .past ? .tertiary : .secondary
                )
            }

            Spacer()
        }
        .padding(.vertical, 3)
        .opacity(state == .past ? 0.58 : 1.0)
    }

    private enum StageState {
        case past
        case current
        case future
    }

    private func stageState(_ stage: Stage) -> StageState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.startOfDay(for: stage.startDate)
        let end = calendar.startOfDay(for: stage.endDate)

        if today > end { return .past }
        if today >= start && today <= end { return .current }
        return .future
    }

    private func seasonContainsToday(_ season: Season) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if season.stages.contains(where: { stageState($0) == .current }) {
            return true
        }

        if
            let first = season.stages.map(\.startDate).min(),
            let last = season.stages.map(\.endDate).max()
        {
            let start = calendar.startOfDay(for: first)
            let end = calendar.startOfDay(for: last)

            return today >= start && today <= end
        }

        // Declared years are only a fallback for a season with no stages.
        guard season.stages.isEmpty,
              let startYear = season.declaredStartYear
        else {
            return false
        }

        let endYear = season.declaredEndYear ?? startYear
        let currentYear = calendar.component(.year, from: today)

        return currentYear >= startYear && currentYear <= endYear
    }

    private func configureInitialExpansion() {
        guard !didConfigureInitialExpansion else { return }
        didConfigureInitialExpansion = true

        if let currentSeason =
            sortedSeasons.first(where: { seasonContainsToday($0) }) {
            expandedSeasonIDs.insert(currentSeason.persistentModelID)
        }
    }

    private func toggleSeason(_ season: Season) {
        let id = season.persistentModelID

        if expandedSeasonIDs.contains(id) {
            expandedSeasonIDs.remove(id)
        } else {
            expandedSeasonIDs.insert(id)
        }
    }

    private func sortedStages(for season: Season) -> [Stage] {
        season.stages.sorted { $0.startDate < $1.startDate }
    }

    private func stageDateText(_ stage: Stage) -> String {
        let calendar = Calendar.current

        if calendar.isDate(stage.startDate, inSameDayAs: stage.endDate) {
            return stage.startDate.formatted(
                .dateTime.day().month(.abbreviated)
            )
        }

        return
            stage.startDate.formatted(
                .dateTime.day().month(.abbreviated)
            )
            + " – "
            + stage.endDate.formatted(
                .dateTime.day().month(.abbreviated)
            )
    }

    private func stagesCountText(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100

        if mod10 == 1 && mod100 != 11 {
            return "\(count) этап"
        }

        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return "\(count) этапа"
        }

        return "\(count) этапов"
    }
}
