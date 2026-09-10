import SwiftUI
import SwiftData

struct SeasonDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let season: Season

    @State private var showingAddStage = false
    @State private var stageToEdit: Stage?

    private var sortedStages: [Stage] {
        season.stages.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        List {
            if sortedStages.isEmpty {
                ContentUnavailableView(
                    "Нет этапов",
                    systemImage: "flag.checkered",
                    description: Text("Добавь первый этап сезона")
                )
            } else {
                ForEach(sortedStages) { stage in
                    NavigationLink {
                        StageDetailView(stage: stage)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(stage.name)
                                    .font(.headline)

                                if stage.scheduleUpdatedAt != nil {
                                    Text("ОБНОВЛЕНО")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let circuit = stage.circuit {
                                Text(circuit.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text(
                                "\(stage.startDate.formatted(date: .abbreviated, time: .omitted)) — \(stage.endDate.formatted(date: .abbreviated, time: .omitted))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteStage(stage)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }

                        Button {
                            stageToEdit = stage
                        } label: {
                            Label("Изменить", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Сезон \(String(season.year))")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddStage = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddStage) {
            AddStageView(season: season)
        }
        .sheet(item: $stageToEdit) { stage in
            EditStageView(stage: stage)
        }
    }

    private func deleteStage(_ stage: Stage) {
        modelContext.delete(stage)

        do {
            try modelContext.save()
        } catch {
            print("Ошибка удаления этапа: \(error)")
        }
    }
}
