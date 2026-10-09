import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct AddCircuitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let circuit: Circuit?
    @State private var name: String
    @State private var shortName: String
    @State private var city: String
    @State private var country: String
    @State private var length: String
    @State private var website: String
    @State private var description: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var coordinateNote: String
    @State private var logo: Data?
    @State private var importingLogo = false
    @State private var error: String?
    init(circuit: Circuit? = nil) {
        self.circuit = circuit
        _name = State(initialValue: circuit?.name ?? "")
        _shortName = State(initialValue: circuit?.shortName ?? "")
        _city = State(initialValue: circuit?.city ?? "")
        _country = State(initialValue: circuit?.country ?? "")
        _length = State(initialValue: circuit?.lengthMeters.map { String($0) } ?? "")
        _website = State(initialValue: circuit?.website ?? "")
        _description = State(initialValue: circuit?.circuitDescription ?? "")
        _latitude = State(initialValue: circuit?.latitude.map { String($0) } ?? "")
        _longitude = State(initialValue: circuit?.longitude.map { String($0) } ?? "")
        _coordinateNote = State(initialValue: circuit?.coordinateNote ?? "")
        _logo = State(initialValue: circuit?.logoData)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Автодром") {
                    TextField("Название", text: $name)
                    TextField("Сокращение", text: $shortName)
                    TextField("Город", text: $city)
                    TextField("Страна", text: $country)
                    TextField("Длина, метры (необязательно)", text: $length).keyboardType(.decimalPad)
                }
                Section("Информация (необязательно)") {
                    TextField("Сайт: https://…", text: $website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Описание", text: $description, axis: .vertical).lineLimit(3...8)
                }
                Section("Точка назначения (необязательно)") {
                    TextField("Широта", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("Долгота", text: $longitude).keyboardType(.numbersAndPunctuation)
                    TextField("Примечание: въезд, парковка…", text: $coordinateNote)
                    Text("Лучше указать въезд или парковку. Координаты вводятся десятичными градусами.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Логотип (необязательно)") {
                    if let logo { CatalogLogo(data: logo, symbol: "road.lanes").frame(height: 80) }
                    Button("Загрузить PNG или JPEG") { importingLogo = true }
                    if logo != nil { Button("Удалить логотип", role: .destructive) { logo = nil } }
                }
            }
            .navigationTitle(circuit == nil ? "Новый автодром" : "Редактировать автодром")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .fileImporter(isPresented: $importingLogo, allowedContentTypes: [.png, .jpeg]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 5 * 1024 * 1024, let image = UIImage(data: data) else {
                        throw CircuitSchemeRenderer.RenderError.invalid
                    }
                    logo = image.pngData()
                } catch { self.error = error.localizedDescription }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func number(_ value: String) -> Double? { Double(value.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) }
    private func save() {
        let meters = number(length), lat = number(latitude), lon = number(longitude)
        guard length.isEmpty || (meters != nil && meters!.isFinite && meters! > 0 && meters! <= 100_000) else { error = "Укажите положительную длину в метрах или оставьте поле пустым."; return }
        guard (latitude.isEmpty && longitude.isEmpty) || (lat != nil && lon != nil && lat!.isFinite && lon!.isFinite && (-90...90).contains(lat!) && (-180...180).contains(lon!)) else { error = "Укажите обе координаты или оставьте оба поля пустыми."; return }
        let site = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard site.isEmpty || (URL(string: site)?.host != nil && ["https", "http"].contains(URL(string: site)?.scheme ?? "")) else { error = "Адрес сайта должен начинаться с https:// или http://."; return }
        let target = circuit ?? Circuit(name: name)
        if circuit == nil { modelContext.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.shortName = shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        target.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        target.lengthMeters = meters; target.website = site; target.circuitDescription = description
        target.latitude = lat; target.longitude = lon; target.coordinateNote = coordinateNote; target.logoData = logo
        do { try modelContext.save(); dismiss() } catch { modelContext.rollback(); self.error = error.localizedDescription }
    }
}
