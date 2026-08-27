import SwiftUI
import SwiftData

struct ChampionshipDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let championship: Championship

    @State private var showingAddSeason = false

    var body: some View {
        List {
            if championship.seasons.isEmpty {
                ContentUnavailableView(
                    "Нет сезонов",
                    systemImage: "calendar",
                    description: Text("Добавь первый сезон")
                )
            } else {
                ForEach(
                    championship.seasons.sorted { $0.year > $1.year }
                ) { season in
                    NavigationLink {
                        SeasonDetailView(season: season)
                    } label: {
                        HStack {
                            Text(String(season.year))
                                .font(.headline)

                            Spacer()

                            Text("\(season.stages.count) этапов")
                                .foregroundStyle(.secondary)
                        }
                    }
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
            AddSeasonView(championship: championship)
        }
    }
}
