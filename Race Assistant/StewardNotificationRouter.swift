import SwiftUI
import SwiftData
import Combine

struct StewardOpenRequest: Identifiable {
    let id: UUID
}
@MainActor
final class StewardNotificationRouter: ObservableObject {
    static let shared = StewardNotificationRouter()
    @Published var request: StewardOpenRequest?
}
struct StewardNotificationDestination: View {
    @Environment(\.modelContext) private var context
    let request: StewardOpenRequest
    var body: some View {
        NavigationStack {
            if let incident = (try? context.fetch(FetchDescriptor<StewardIncident>()))?.first(where: { $0.incidentID == request.id }) {
                StewardIncidentDetailView(incident: incident)
            } else {
                ContentUnavailableView("Инцидент не найден", systemImage: "checklist", description: Text("Возможно, запись или этап уже удалены."))
            }
        }
    }
}
