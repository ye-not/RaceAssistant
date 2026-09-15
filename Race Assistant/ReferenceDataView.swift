import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ReferenceDataView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = JSONExportDocument(data: Data())
    @State private var message: String?

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

            Section {
                HStack(spacing: 8) {
                    Spacer()

                    Button("Загрузить JSON") {
                        showingImporter = true
                    }

                    Text("·")

                    Button("Скачать JSON") {
                        prepareExport()
                    }

                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Справочники")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importJSON(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "RaceAssistant_Export.json"
        ) { result in
            switch result {
            case .success:
                message = "JSON сохранён"
            case .failure(let error):
                message = "Ошибка экспорта: \(error.localizedDescription)"
            }
        }
        .alert(
            "Race Assistant",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func importJSON(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            let imported = try SeedDataImporter.importExternalJSON(
                from: url,
                modelContext: modelContext
            )

            message = "Обновлено этапов: \(imported.stageCount), событий: \(imported.eventCount)"
        } catch {
            message = "Ошибка импорта: \(error.localizedDescription)"
        }
    }

    private func prepareExport() {
        do {
            let data = try SeedDataImporter.exportCurrentJSON(
                modelContext: modelContext
            )
            exportDocument = JSONExportDocument(data: data)
            showingExporter = true
        } catch {
            message = "Ошибка экспорта: \(error.localizedDescription)"
        }
    }
}

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
