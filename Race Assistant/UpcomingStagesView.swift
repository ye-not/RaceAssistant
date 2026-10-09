import SwiftUI
import SwiftData

struct UpcomingStagesView: View {
    @Query private var stages: [Stage]
    @State private var seriesFilter = ""
    @State private var circuitFilter = ""
    @State private var sortOrder = 0
    @State private var interestedOnly = false
    @State private var search = ""
    @State private var configuring = false

    private var upcoming: [Stage] { SchedulePresentation.upcoming(stages, now: .now) }
    private var seriesNames: [String] { Array(Set(upcoming.compactMap { $0.season?.championship?.name })).sorted() }
    private var circuitNames: [String] { Array(Set(upcoming.compactMap { $0.circuit?.name })).sorted() }

    private var visible: [Stage] {
        upcoming.filter { stage in
            (seriesFilter.isEmpty || stage.season?.championship?.name == seriesFilter) &&
            (circuitFilter.isEmpty || stage.circuit?.name == circuitFilter) &&
            (!interestedOnly || stage.isInterested) &&
            (search.isEmpty || [stage.name, stage.season?.championship?.name ?? "", stage.circuit?.name ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }.sorted { lhs, rhs in
            if lhs.isInterested != rhs.isInterested { return lhs.isInterested }
            if sortOrder == 1 {
                let a = lhs.season?.championship?.name ?? "", b = rhs.season?.championship?.name ?? ""
                if a != b { return a < b }
            }
            if sortOrder == 2 {
                let a = lhs.circuit?.name ?? "", b = rhs.circuit?.name ?? ""
                if a != b { return a < b }
            }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        List {
            Section("Мои этапы") { stageRows(visible.filter(\.isInterested)) }
            if !interestedOnly {
                Section("Другие этапы") { stageRows(visible.filter { !$0.isInterested }) }
            }
            if visible.isEmpty { Text("Этапов с такими условиями нет").foregroundStyle(.secondary) }
        }
        .searchable(text: $search, prompt: "Этап, серия или автодром")
        .navigationTitle("Текущие и предстоящие этапы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { configuring = true } label: { Label("Настроить", systemImage: "slider.horizontal.3") } }
        .sheet(isPresented: $configuring) { settings }
    }

    private func stageRows(_ values: [Stage]) -> some View {
        ForEach(values) { stage in
            NavigationLink { StageDetailView(stage: stage) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(stage.season?.championship?.name ?? "")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(stage.name).font(.headline)
                    Text("\(stage.startDate.formatted(date: .abbreviated, time: .omitted)) – \(stage.endDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let circuit = stage.circuit { Label(circuit.name, systemImage: "road.lanes").font(.caption).foregroundStyle(.secondary) }
                    if stage.isInterested { Label(stage.participationTitle, systemImage: stage.participation.symbol).font(.caption).foregroundStyle(.orange) }
                }
            }
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Toggle("С выбранным участием", isOn: $interestedOnly)
                Picker("Сортировка внутри разделов", selection: $sortOrder) {
                    Text("По дате").tag(0)
                    Text("По серии").tag(1)
                    Text("По автодрому").tag(2)
                }
                NavigationLink {
                    SearchableOptionsView(title: "Серия", allTitle: "Все серии", options: seriesNames, selection: $seriesFilter)
                } label: { LabeledContent("Серия", value: seriesFilter.isEmpty ? "Все (\(seriesNames.count))" : seriesFilter) }
                NavigationLink {
                    SearchableOptionsView(title: "Автодром", allTitle: "Все автодромы", options: circuitNames, selection: $circuitFilter)
                } label: { LabeledContent("Автодром", value: circuitFilter.isEmpty ? "Все (\(circuitNames.count))" : circuitFilter) }
                Button("Сбросить фильтры") { seriesFilter = ""; circuitFilter = ""; interestedOnly = false; sortOrder = 0 }
                Text("Сначала показаны этапы с выбранным участием. Мои этапы — те, где выбрано участие официального лица, спортсмена или зрителя. Автодромы перечислены для всех текущих и предстоящих этапов, независимо от текущего фильтра.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Фильтры и сортировка")
            .toolbar { Button("Готово") { configuring = false } }
        }
    }
}
