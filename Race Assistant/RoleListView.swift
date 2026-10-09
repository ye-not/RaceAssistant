import SwiftUI
import SwiftData

struct RoleListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Role.name)
    private var roles: [Role]

    @State private var showingAddRole = false

    @State private var search = ""
    private var visible: [Role] {
        roles.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.shortName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if roles.isEmpty {
                ContentUnavailableView(
                    "Нет ролей",
                    systemImage: "person.2",
                    description: Text("Добавь первую роль")
                )
            } else {
                ForEach(visible) { role in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.name)
                                .font(.headline)

                            if !role.shortName.isEmpty {
                                Text(role.shortName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { role.active },
                                set: { newValue in
                                    role.active = newValue
                                    saveChanges()
                                }
                            )
                        )
                        .labelsHidden()
                    }
                }
                .onDelete(perform: deleteRoles)
            }
        }
        .searchable(text: $search, prompt: "Поиск")
        .navigationTitle("Роли")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddRole = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddRole) {
            AddRoleView()
        }
    }

    private func deleteRoles(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(visible[index])
        }

        saveChanges()
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Ошибка сохранения ролей: \(error)")
        }
    }
}
