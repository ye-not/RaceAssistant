import SwiftUI
import UIKit
import SwiftData

struct CatalogLogo: View {
    let data: Data?
    let symbol: String
    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().padding(5).background(.white)
            } else {
                Image(systemName: symbol).resizable().scaledToFit().padding(10).foregroundStyle(.secondary)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CircuitInformationSection: View {
    @Environment(\.openURL) private var openURL
    let circuit: Circuit
    @State private var choosingNavigator = false
    var body: some View {
        Section("Об автодроме") {
            CatalogLogo(data: circuit.logoData, symbol: "road.lanes").frame(height: 70).frame(maxWidth: .infinity)
            Text(circuit.name).font(.headline)
            Text([circuit.city, circuit.country].filter { !$0.isEmpty }.joined(separator: ", ")).foregroundStyle(.secondary)
            if let length = circuit.defaultConfiguration?.lengthMeters ?? circuit.lengthMeters {
                LabeledContent("Длина", value: String(format: "%.3f км", length / 1000))
            }
            if !circuit.circuitDescription.isEmpty { Text(circuit.circuitDescription) }
            if let url = URL(string: circuit.website), ["https", "http"].contains(url.scheme ?? "") {
                Link(destination: url) { Label("Сайт автодрома", systemImage: "globe") }
            }
            if circuit.hasCoordinates {
                Button("Построить маршрут", systemImage: "arrow.triangle.turn.up.right.diamond") { choosingNavigator = true }
                if !circuit.coordinateNote.isEmpty { Text(circuit.coordinateNote).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .confirmationDialog("Открыть маршрут", isPresented: $choosingNavigator, titleVisibility: .visible) {
            Button("Apple Карты") { navigate("apple") }
            if UIApplication.shared.canOpenURL(URL(string: "yandexnavi://")!) {
                Button("Яндекс Навигатор") { navigate("yandexnavi") }
            }
            if UIApplication.shared.canOpenURL(URL(string: "yandexmaps://")!) {
                Button("Яндекс Карты") { navigate("yandexmaps") }
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    private func navigate(_ provider: String) {
        guard circuit.hasCoordinates, let lat = circuit.latitude, let lon = circuit.longitude else { return }
        var components = URLComponents()
        if provider == "yandexnavi" {
            components.scheme = "yandexnavi"; components.host = "build_route_on_map"
            components.queryItems = [URLQueryItem(name: "lat_to", value: String(lat)), URLQueryItem(name: "lon_to", value: String(lon))]
        } else if provider == "yandexmaps" {
            components.scheme = "yandexmaps"; components.host = "maps.yandex.ru"
            components.queryItems = [URLQueryItem(name: "rtext", value: "~\(lat),\(lon)"), URLQueryItem(name: "rtt", value: "auto")]
        } else {
            components.scheme = "https"; components.host = "maps.apple.com"
            components.queryItems = [URLQueryItem(name: "daddr", value: "\(lat),\(lon)"), URLQueryItem(name: "dirflg", value: "d")]
        }
        if let url = components.url { openURL(url) }
    }
}

struct StageCircuitInfoView: View {
    let stage: Stage
    let circuit: Circuit
    var body: some View {
        List {
            if let configuration = stage.effectiveConfiguration, configuration.schemeData != nil {
                Section("Схема трассы") {
                    if let data = configuration.schemeData {
                        CircuitSchemePreview(data: data, mime: configuration.schemeMIMEType ?? "image/png")
                            .frame(height: 280)
                    }
                    NavigationLink {
                        CircuitSchemeView(configuration: configuration)
                    } label: {
                        Label("Открыть на весь экран", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
            }
            CircuitInformationSection(circuit: circuit)
        }
        .navigationTitle(circuit.shortName.isEmpty ? circuit.name : circuit.shortName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
