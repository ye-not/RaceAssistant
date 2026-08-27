import SwiftUI

struct ReferenceDataView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    CircuitListView()
                } label: {
                    Label("Автодромы", systemImage: "road.lanes")
                }
                NavigationLink {
                    RoleListView()
                } label: {
                    Label("Роли", systemImage: "person.2")
                }
                NavigationLink {
                    RaceClassListView()
                } label: {
                    Label("Классы соревнований", systemImage: "car.2")
                }
            }
        }
        .navigationTitle("Справочники")
    }
}
