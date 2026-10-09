import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import PDFKit
import WebKit

struct ConfigurationPicker: View {
    let circuit: Circuit
    @Binding var selection: CircuitConfiguration?
    var inherited: CircuitConfiguration? = nil
    var usesStageDefault = false
    var showsSchemeLink = true

    private var choices: [CircuitConfiguration] {
        circuit.configurations.filter { !$0.isArchived || $0 === selection }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        Picker("Конфигурация", selection: $selection) {
            Text(usesStageDefault ? "Как у этапа" : "По умолчанию / пропустить")
                .tag(nil as CircuitConfiguration?)
            ForEach(choices) { config in
                Text(config.name + (config.isArchived ? " (архив)" : ""))
                    .tag(config as CircuitConfiguration?)
            }
        }
        if let resolved = selection ?? (usesStageDefault ? inherited : circuit.defaultConfiguration) {
            Text("\(resolved.name) · \(configurationLength(resolved.lengthMeters))")
                .font(.caption).foregroundStyle(.secondary)
            if showsSchemeLink && resolved.schemeData != nil {
                NavigationLink("Посмотреть схему") { CircuitSchemeView(configuration: resolved) }
            }
        } else {
            Text("Конфигурация не указана. \(configurationLength(circuit.lengthMeters))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private func configurationLength(_ length: Double?) -> String {
    guard let length, length > 0 else { return "Длина не указана" }
    return "\(length.formatted(.number.precision(.fractionLength(0...2)))) м"
}

struct CircuitDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var stages: [Stage]
    @Query private var events: [ScheduleEvent]
    let circuit: Circuit
    @State private var editingCircuit = false
    @State private var adding = false
    @State private var editing: CircuitConfiguration?
    @State private var errorMessage: String?
    @State private var notice: String?

    var body: some View {
        List {
            CircuitInformationSection(circuit: circuit)
            configurationsSection
            addConfigurationSection
        }
        .navigationTitle(circuit.shortName.isEmpty ? circuit.name : circuit.shortName)
        .toolbar { Button("Редактировать") { editingCircuit = true } }
        .sheet(isPresented: $editingCircuit) { AddCircuitView(circuit: circuit) }
        .sheet(isPresented: $adding) { EditCircuitConfigurationView(circuit: circuit) }
        .sheet(item: $editing) { EditCircuitConfigurationView(circuit: circuit, configuration: $0) }
        .alert("Конфигурация", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") { notice = nil }
        } message: { Text(notice ?? "") }
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var sortedConfigurations: [CircuitConfiguration] {
        circuit.configurations.sorted { $0.name < $1.name }
    }

    private var circuitSection: some View {
        Section("Автодром") {
            Text(circuit.name).font(.headline)
            Text([circuit.city, circuit.country].filter { !$0.isEmpty }.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }
    }

    private var configurationsSection: some View {
        Section("Конфигурации") {
            if sortedConfigurations.isEmpty {
                Text("Именованных конфигураций нет. Длину можно указать в карточке автодрома.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sortedConfigurations) { config in
                configurationRow(config)
            }
        }
    }

    private func configurationRow(_ config: CircuitConfiguration) -> some View {
        Button {
            editing = config
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(config.name).foregroundStyle(.primary)
                    if circuit.defaultConfiguration === config {
                        Text("Основная").font(.caption).foregroundStyle(.secondary)
                    }
                    if config.isArchived {
                        Text("Архив").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(configurationLength(config.lengthMeters))
                    .font(.caption).foregroundStyle(.secondary)
                if config.schemeData != nil {
                    Label("Есть схема", systemImage: "map").font(.caption)
                }
            }
        }
        .swipeActions {
            Button("Удалить", role: .destructive) { delete(config) }
        }
    }

    private var addConfigurationSection: some View {
        Section {
            Button("Добавить конфигурацию", systemImage: "plus") { adding = true }
        } footer: {
            Text("Основная конфигурация используется, если на этапе не выбрана другая. Конфигурации, связанные с этапами или гонками, при удалении переходят в архив.")
        }
    }

    private func delete(_ config: CircuitConfiguration) {
        let wasDefault = circuit.defaultConfiguration === config
        let linkedStages = stages.filter { $0.effectiveConfiguration === config }
        let used = !linkedStages.isEmpty || events.contains { $0.effectiveConfiguration === config }
        if used {
            // Freeze inherited selections before choosing a new default.
            for stage in linkedStages where stage.circuitConfiguration == nil { stage.circuitConfiguration = config }
            config.isArchived = true
        } else {
            circuit.configurations.removeAll { $0 === config }
            modelContext.delete(config)
        }
        if wasDefault {
            circuit.defaultConfiguration = circuit.configurations.filter { !$0.isArchived && $0 !== config }
                .sorted { $0.name < $1.name }.first
        }
        do {
            try modelContext.save()
            if used { notice = "Конфигурация перенесена в архив. Существующие этапы и гонки сохраняют её; для новых она недоступна." }
        } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
}

struct EditCircuitConfigurationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let circuit: Circuit
    let configuration: CircuitConfiguration?
    @State private var name: String
    @State private var length: String
    @State private var isDefault: Bool
    @State private var archived: Bool
    @State private var scheme: Data?
    @State private var mime: String?
    @State private var importing = false
    @State private var errorMessage: String?

    init(circuit: Circuit, configuration: CircuitConfiguration? = nil) {
        self.circuit = circuit
        self.configuration = configuration
        _name = State(initialValue: configuration?.name ?? "")
        _length = State(initialValue: configuration?.lengthMeters.map { String($0) } ?? "")
        _isDefault = State(initialValue: configuration.map { circuit.defaultConfiguration === $0 } ?? circuit.configurations.isEmpty)
        _archived = State(initialValue: configuration?.isArchived ?? false)
        _scheme = State(initialValue: configuration?.schemeData)
        _mime = State(initialValue: configuration?.schemeMIMEType)
    }
    private var parsedLength: Double? { Double(length.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) }
    private var valid: Bool {
        guard let value = parsedLength else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.isFinite && value > 0 && value <= 100_000
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Конфигурация") {
                    TextField("Название", text: $name)
                    TextField("Длина, метры", text: $length).keyboardType(.decimalPad)
                    Toggle("По умолчанию для автодрома", isOn: $isDefault).disabled(archived)
                    if configuration?.isArchived == true { Toggle("В архиве", isOn: $archived) }
                }
                Section("Схема (необязательно)") {
                    if let scheme {
                        CircuitSchemeContent(data: scheme, mime: mime ?? "image/png").id(mime).frame(height: 220)
                        Button("Удалить схему", role: .destructive) { self.scheme = nil; mime = nil }
                    }
                    Button(scheme == nil ? "Загрузить схему" : "Заменить схему") { importing = true }
                    Text("SVG, PDF, PNG или JPEG. Файл сохраняется в приложении и доступен без интернета.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(configuration == nil ? "Новая конфигурация" : "Конфигурация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(!valid) }
            }
            .onChange(of: archived) { _, value in if value { isDefault = false } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.svg, .pdf, .png, .jpeg]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= 10 * 1024 * 1024 else { throw SchemeError.tooLarge }
                    let ext = url.pathExtension.lowercased()
                    if ext == "svg" {
                        guard let text = String(data: data, encoding: .utf8), text.contains("<svg") else { throw SchemeError.invalid }
                        mime = "image/svg+xml"
                    } else if ext == "pdf" {
                        guard let document = PDFDocument(data: data), document.pageCount > 0 else { throw SchemeError.invalid }
                        mime = "application/pdf"
                    } else {
                        guard UIImage(data: data) != nil else { throw SchemeError.invalid }
                        mime = ext == "png" ? "image/png" : "image/jpeg"
                    }
                    scheme = data
                } catch { errorMessage = error.localizedDescription }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
    private func save() {
        guard valid, let meters = parsedLength else { return }
        let target = configuration ?? CircuitConfiguration(name: "", circuit: circuit)
        if configuration == nil { modelContext.insert(target); circuit.configurations.append(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.lengthMeters = meters
        target.schemeData = scheme
        target.schemeMIMEType = mime
        target.isArchived = archived
        if isDefault && !archived { circuit.defaultConfiguration = target }
        else if circuit.defaultConfiguration === target { circuit.defaultConfiguration = nil }
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
    private enum SchemeError: LocalizedError {
        case tooLarge, invalid
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Схема должна быть не больше 10 МБ."
            case .invalid: return "Не удалось прочитать схему."
            }
        }
    }
}

struct CircuitSchemeView: View {
    let configuration: CircuitConfiguration
    var body: some View {
        Group {
            if let data = configuration.schemeData {
                CircuitSchemeContent(data: data, mime: configuration.schemeMIMEType ?? "image/png")
            } else {
                ContentUnavailableView("Схема не загружена", systemImage: "map")
            }
        }
        .navigationTitle(configuration.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CircuitSchemeContent: UIViewRepresentable {
    let data: Data
    let mime: String
    func makeUIView(context: Context) -> UIView {
        if mime == "application/pdf" {
            let view = PDFView()
            view.autoScales = true
            return view
        }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        if let view = uiView as? PDFView {
            if context.coordinator.data != data { view.document = PDFDocument(data: data) }
        } else if let view = uiView as? WKWebView, context.coordinator.data != data {
            let html = CircuitSchemeMarkup.html(data, mime: mime, fitViewport: true)
            view.loadHTMLString(html, baseURL: nil)
        }
        context.coordinator.data = data
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let view = uiView as? WKWebView { view.stopLoading(); view.navigationDelegate = nil }
        if let view = uiView as? PDFView { view.document = nil }
    }
    final class Coordinator { var data: Data? }
}

/// A list preview has no embedded web process; vector viewing is opened separately.
struct CircuitSchemePreview: View {
    let data: Data
    let mime: String
    @State private var image: UIImage?
    @State private var errorText: String?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView("Загрузка схемы…")
            }
        }
        .task(id: data) {
            image = nil; errorText = nil
            do {
                let rendered = try await CircuitSchemeRenderer.image(data: data, mime: mime)
                guard !Task.isCancelled else { return }
                image = rendered
            } catch {
                guard !Task.isCancelled else { return }
                errorText = error.localizedDescription
            }
        }
    }
}
