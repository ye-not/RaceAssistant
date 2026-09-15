import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StageScheduleFilesView: View {
    @Environment(\.modelContext) private var modelContext
    let stage: Stage
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = JSONExportDocument(data: Data())
    @State private var message: String?

    private var bundledURL: URL? {
        guard let seedURL = Bundle.main.url(forResource: "RaceAssistantSeed", withExtension: "json"),
              let data = try? Data(contentsOf: seedURL),
              let seed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let names = seed["scheduleFiles"] as? [String] else { return nil }
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let schedules = file["scheduleImports"] as? [[String: Any]] else { continue }
            if schedules.contains(where: {
                $0["stageName"] as? String == stage.name &&
                $0["seriesName"] as? String == stage.season?.championship?.name &&
                ($0["seasonYear"] as? Int == stage.season?.year || $0["seasonName"] as? String == stage.season?.displayName)
            }) { return url }
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                Button("Скачать JSON этого этапа") { export() }
                Button("Загрузить JSON этого этапа") { showingImporter = true }
                if let url = bundledURL {
                    Text(bundleDescription(url)).font(.caption).foregroundStyle(.secondary)
                    Button("Загрузить расписание из приложения") { importFile(url) }
                }
            } header: {
                Text(stage.name)
            } footer: {
                Text("Загрузка обновляет только этот этап. Роль, настройки и записи SC сохраняются. Если гонку с записями SC нельзя сопоставить, обновление отменяется.")
            }
        }
        .navigationTitle("Расписание этапа")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importFile(url)
            case .failure(let error): message = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "RaceAssistant_\(stage.name).json") { result in
            switch result {
            case .success: message = "Файл этапа сохранён"
            case .failure(let error): message = error.localizedDescription
            }
        }
        .alert("Расписание", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }
    private func bundleDescription(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url),
              let file = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "" }
        if let version = file["sourceVersion"] as? Int, let date = file["sourceDate"] as? String {
            return "В приложении: версия \(version) от \(date)"
        }
        return "В приложении: \(url.deletingPathExtension().lastPathComponent)"
    }
    private func export() {
        do {
            exportDocument = JSONExportDocument(data: try SeedDataImporter.exportCurrentJSON(modelContext: modelContext, stage: stage))
            showingExporter = true
        } catch { message = error.localizedDescription }
    }
    private func importFile(_ url: URL) {
        do {
            let result = try SeedDataImporter.importExternalJSON(from: url, modelContext: modelContext, expectedStage: stage)
            message = "Обновлено событий: \(result.eventCount)"
        } catch { message = error.localizedDescription }
    }
}
