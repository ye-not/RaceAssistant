import SwiftUI
import SwiftData

enum StageParticipation: String, CaseIterable, Codable {
    case unspecified, official, athlete, spectator

    var title: String {
        switch self {
        case .unspecified: return "Не выбрано"
        case .official: return "Официальное лицо"
        case .athlete: return "Спортсмен"
        case .spectator: return "Зритель"
        }
    }

    var symbol: String {
        switch self {
        case .unspecified: return "person.crop.circle.badge.questionmark"
        case .official: return "person.badge.shield.checkmark"
        case .athlete: return "car.side"
        case .spectator: return "eye"
        }
    }
}

struct StageParticipationSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Role.name) private var roles: [Role]
    let stage: Stage
    @AppStorage("spectatorRaceStartEnabled") private var spectatorRaceStartEnabled = true

    private var category: Binding<StageParticipation> {
        Binding(get: { stage.participation }, set: { value in
            stage.participation = value
            if value != .official { stage.myRole = nil }
            persist()
        })
    }

    private var role: Binding<Role?> {
        Binding(get: { stage.myRole }, set: {
            stage.myRole = $0
            persist()
        })
    }

    private var classes: [RaceClass] {
        let available = stage.scheduleEvents.flatMap { $0.eventClasses.compactMap(\.raceClass) }
            + (stage.season?.championship?.raceClasses ?? []) + stage.participationClasses
        var unique: [RaceClass] = []
        for value in available where !unique.contains(where: { $0 === value }) { unique.append(value) }
        return unique.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Section("Моё участие") {
            Picker("Участие на этапе", selection: category) {
                ForEach(StageParticipation.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
            if stage.participation == .official {
                Picker("Служебная роль", selection: role) {
                    Text("Не выбрана").tag(nil as Role?)
                    ForEach(roles.filter { $0.active || $0 === stage.myRole }) { value in
                        Text(value.shortName.isEmpty ? value.name : "\(value.name) (\(value.shortName))")
                            .tag(value as Role?)
                    }
                }
            }
            if stage.participation == .spectator {
                Toggle("Уведомлять о начале заездов", isOn: $spectatorRaceStartEnabled)
                    .onChange(of: spectatorRaceStartEnabled) { _, _ in
                        Task { await NotificationManager.shared.rescheduleNotifications(for: stage) }
                    }
                Text("Уведомление в запланированное время старта. Без выбранных классов — все гонки этапа.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if stage.participation == .athlete || stage.participation == .spectator {
                ForEach(classes) { value in
                    Toggle(value.shortName.isEmpty ? value.name : value.shortName,
                           isOn: Binding(get: { stage.participationClasses.contains { $0 === value } }, set: { selected in
                        if selected { stage.participationClasses.append(value) }
                        else { stage.participationClasses.removeAll { $0 === value } }
                        persist()
                    }))
                }
                if stage.participationClasses.isEmpty {
                    Text(classes.isEmpty ? "Классы появятся после добавления расписания или классов чемпионата." : (stage.participation == .spectator ? "Классы не выбраны: уведомления обо всех гонках этапа." : "Выберите классы, в которых участвуете."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func persist() {
        do {
            try modelContext.save()
            PhoneWatchConnectivityManager.shared.sendPreferredStage()
            Task { await NotificationManager.shared.rescheduleNotifications(for: stage) }
        } catch { modelContext.rollback() }
    }
}
