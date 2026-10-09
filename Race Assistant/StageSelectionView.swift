import SwiftUI
import SwiftData

struct StageSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var stages: [Stage]
    @State private var search = ""
    let onSelect: (Stage?) -> Void

    private var series: [String] {
        Array(Set(stages.compactMap { $0.season?.championship?.name })).sorted()
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("Автоматический выбор") { onSelect(nil); dismiss() }
                ForEach(series, id: \.self) { name in
                    NavigationLink {
                        SeriesStageSelectionView(seriesName: name, stages: stages) { stage in
                            onSelect(stage)
                            dismiss()
                        }
                    } label: { Text(name) }
                }
            }
            .searchable(text: $search, prompt: "Найти серию")
            .navigationTitle("Выберите серию")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
}

private struct SeriesStageSelectionView: View {
    let seriesName: String
    let stages: [Stage]
    let onSelect: (Stage) -> Void
    @State private var search = ""

    private var visible: [Stage] {
        stages.filter {
            $0.season?.championship?.name == seriesName &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) ||
             ($0.circuit?.name ?? "").localizedCaseInsensitiveContains(search))
        }.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        List(visible) { stage in
            Button { onSelect(stage) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name).foregroundStyle(.primary)
                    Text("\(stage.season?.displayName ?? "") · \(stage.startDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    if stage.isInterested { Text(stage.participationTitle).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
        .searchable(text: $search, prompt: "Найти этап или автодром")
        .navigationTitle(seriesName)
    }
}

struct SearchableOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let allTitle: String
    let options: [String]
    @Binding var selection: String
    @State private var search = ""

    var body: some View {
        List {
            option("", label: allTitle)
            ForEach(options.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { value in
                option(value, label: value)
            }
        }
        .searchable(text: $search, prompt: "Поиск")
        .navigationTitle(title)
    }

    private func option(_ value: String, label: String) -> some View {
        Button { selection = value; dismiss() } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if selection == value { Image(systemName: "checkmark") }
            }
        }
    }
}

struct ChampionshipManagementView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Championship.name) private var championships: [Championship]
    @State private var search = ""
    @State private var adding = false

    private var visible: [Championship] {
        championships.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(visible) { championship in
                NavigationLink { ChampionshipDetailView(championship: championship) } label: { Text(championship.name) }
            }
            .onDelete { indices in
                let removing = indices.map { visible[$0] }
                for championship in removing {
                    for event in championship.seasons.flatMap(\.stages).flatMap(\.scheduleEvents) {
                        NotificationManager.shared.removeNotifications(for: event)
                    }
                    context.delete(championship)
                }
                do {
                    try context.save()
                    PhoneWatchConnectivityManager.shared.sendPreferredStage()
                } catch { context.rollback() }
            }
        }
        .searchable(text: $search, prompt: "Найти чемпионат")
        .navigationTitle("Чемпионаты")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { AddChampionshipView() }
    }
}
