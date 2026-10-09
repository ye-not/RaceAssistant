import SwiftUI
import SwiftData

struct CircuitListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Circuit.name)
    private var circuits: [Circuit]

    @Query private var stages: [Stage]
    @State private var errorMessage: String?
    @State private var showingAddCircuit = false

    @State private var search = ""
    private var visible: [Circuit] {
        circuits.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.shortName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if circuits.isEmpty {
                ContentUnavailableView(
                    "Нет автодромов",
                    systemImage: "road.lanes",
                    description: Text("Добавь первый автодром")
                )
            } else {
                ForEach(visible) { circuit in
                    NavigationLink {
                        CircuitDetailView(circuit: circuit)
                    } label: {
                    HStack(spacing: 12) {
                    CatalogLogo(data: circuit.logoData, symbol: "road.lanes").frame(width: 58, height: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(circuit.name)
                            .font(.headline)

                        let length = circuit.defaultConfiguration?.lengthMeters ?? circuit.lengthMeters
                        if let length { Text(String(format: "%.3f км", length / 1000)).font(.subheadline).foregroundStyle(.secondary) }
                        if !circuit.city.isEmpty || !circuit.country.isEmpty {
                            Text(locationText(for: circuit))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    }
                    }
                }
                .onDelete(perform: deleteCircuits)
            }
        }
        .searchable(text: $search, prompt: "Поиск")
        .navigationTitle("Автодромы")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddCircuit = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddCircuit) {
            AddCircuitView()
        }
        .alert("Автодром используется", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func deleteCircuits(offsets: IndexSet) {
        for index in offsets {
            let circuit = visible[index]
            guard !stages.contains(where: { $0.circuit === circuit }) else {
                errorMessage = "Автодром привязан к этапу. Сначала измените автодром этого этапа."
                continue
            }
            modelContext.delete(circuit)
        }
    }

    private func locationText(for circuit: Circuit) -> String {
        [circuit.city, circuit.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
