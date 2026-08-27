import SwiftUI
import SwiftData

struct CircuitListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Circuit.name)
    private var circuits: [Circuit]

    @State private var showingAddCircuit = false

    var body: some View {
        List {
            if circuits.isEmpty {
                ContentUnavailableView(
                    "Нет автодромов",
                    systemImage: "road.lanes",
                    description: Text("Добавь первый автодром")
                )
            } else {
                ForEach(circuits) { circuit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(circuit.name)
                            .font(.headline)

                        if !circuit.city.isEmpty || !circuit.country.isEmpty {
                            Text(locationText(for: circuit))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteCircuits)
            }
        }
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
    }

    private func deleteCircuits(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(circuits[index])
        }
    }

    private func locationText(for circuit: Circuit) -> String {
        [circuit.city, circuit.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
