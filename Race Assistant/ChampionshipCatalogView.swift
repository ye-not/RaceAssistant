import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct ChampionshipTiles: View {
    let championships: [Championship]
    let onSelect: (Championship) -> Void
    private var sorted: [Championship] {
        championships.sorted {
            let a = $0.isFollowed || $0.seasons.contains { $0.stages.contains(where: \.isInterested) }
            let b = $1.isFollowed || $1.seasons.contains { $0.stages.contains(where: \.isInterested) }
            if a != b { return a }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(sorted) { championship in
                Button { onSelect(championship) } label: {
                    VStack(spacing: 8) {
                        CatalogLogo(data: championship.logoData, symbol: "flag.checkered").frame(height: 65)
                        Text(championship.name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.primary)
                        if championship.isFollowed { Label("Интересуюсь", systemImage: "star.fill").font(.caption2).foregroundStyle(.orange) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 112).padding(8)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.borderless)
            }
        }
    }
}

struct ChampionshipCatalogView: View {
    @Query(sort: \Championship.name) private var championships: [Championship]
    @State private var search = ""
    @State private var selectedChampionship: Championship?
    var body: some View {
        ScrollView {
            ChampionshipTiles(championships: championships.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { championship in
                guard selectedChampionship == nil else { return }
                selectedChampionship = championship
            }.padding()
        }
        .navigationDestination(item: $selectedChampionship) { ChampionshipDetailView(championship: $0) }
        .navigationTitle("Гоночные серии")
        .searchable(text: $search, prompt: "Название серии")
    }
}

struct ChampionshipBrandView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let championship: Championship
    @State private var data: Data?
    @State private var website: String
    @State private var importing = false
    @State private var error: String?
    init(championship: Championship) {
        self.championship = championship
        _data = State(initialValue: championship.logoData)
        _website = State(initialValue: championship.website)
    }
    var body: some View {
        Form {
            Section("Серия") {
                CatalogLogo(data: data, symbol: "flag.checkered").frame(height: 90)
                Button("Загрузить логотип PNG / JPEG") { importing = true }
                if data != nil { Button("Удалить логотип", role: .destructive) { data = nil } }
                TextField("Сайт (необязательно)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
        }
        .navigationTitle("Логотип и сайт")
        .toolbar { Button("Сохранить") {
            let site = website.trimmingCharacters(in: .whitespacesAndNewlines)
            guard site.isEmpty || (URL(string: site)?.host != nil && ["https", "http"].contains(URL(string: site)?.scheme ?? "")) else { error = "Укажите адрес https:// или http://"; return }
            championship.logoData = data; championship.website = site
            do { try modelContext.save(); dismiss() } catch { modelContext.rollback(); self.error = error.localizedDescription }
        } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 5 * 1024 * 1024, let image = UIImage(data: bytes) else { throw CircuitSchemeRenderer.RenderError.invalid }
                data = image.pngData()
            } catch { self.error = error.localizedDescription }
        }
        .alert("Ошибка", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
