import SwiftUI
import SwiftData

struct RaceClassListView: View {
    @Query(sort: \RaceClass.name) private var classes: [RaceClass]
    @State private var search = ""
    @State private var adding = false
    @State private var editing: RaceClass?
    var body: some View {
        List {
            Section {
                ForEach(classes.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.shortName.localizedCaseInsensitiveContains(search) }) { item in
                    Button { editing = item } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).foregroundStyle(.primary)
                            Text([item.shortName, item.active ? "" : "В архиве"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: { Text("Нажмите на класс для редактирования. Архивные классы остаются в существующих расписаниях.") }
        }
        .navigationTitle("Классы")
        .searchable(text: $search, prompt: "Название или сокращение")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { AddRaceClassView() }
        .sheet(item: $editing) { AddRaceClassView(raceClass: $0) }
    }
}
