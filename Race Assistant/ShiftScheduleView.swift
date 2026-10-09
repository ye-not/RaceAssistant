import SwiftUI
import SwiftData

struct ShiftScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: ScheduleEvent

    @State private var shiftMinutes = 10
    @State private var scope: ShiftScope = .group

    private enum ShiftScope: String, CaseIterable {
        case event = "Только эта строка"
        case group = "Эта гонка"
        case day = "Остаток дня"
    }

    private let quickOptions = [
        -10,
        -5,
        5,
        10,
        15,
        30,
        45,
        60,
        90,
        120
    ]

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Сдвиг

                Section("Сдвиг") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(quickOptions, id: \.self) { minutes in
                                Button(shiftText(minutes)) { shiftMinutes = minutes }
                                    .buttonStyle(.bordered)
                                    .tint(shiftMinutes == minutes ? Color.orange : Color.gray)
                            }
                        }
                    }

                    TextField("Точно в минутах", value: $shiftMinutes, format: .number)
                        .keyboardType(.numbersAndPunctuation)
                }

                // MARK: - Применить

                Section("Применить") {
                    Picker("Какие строки", selection: $scope) {
                        ForEach(ShiftScope.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    Text("Будет перенесено: \(eventsToShift.count) событий. Прошедшие и завершённые строки сохранят своё время.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Результат

                Section("Результат") {
                    HStack {
                        Text("Было")

                        Spacer()

                        Text(
                            event.plannedStart.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                    }

                    HStack {
                        Text("Станет")

                        Spacer()

                        Text(
                            shiftedDate.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        .fontWeight(.semibold)
                    }
                }
            }
            .navigationTitle(
                "Сдвинуть расписание"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {
                    Button("Применить") {
                        applyShift()
                    }
                    .disabled(
                        shiftMinutes == 0 || eventsToShift.isEmpty
                    )
                }
            }
        }
        .onAppear {
            if event.groupID?.isEmpty != false { scope = .event }
        }
    }

    // MARK: - Shifted Date

    private var shiftedDate: Date {
        Calendar.current.date(
            byAdding: .minute,
            value: shiftMinutes,
            to: event.plannedStart
        ) ?? event.plannedStart
    }

    private var eventsToShift: [ScheduleEvent] {
        guard let stage = event.stage else { return [] }
        let start = event.plannedStart
        let group = event.groupID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        return stage.scheduleEvents.filter { candidate in
            guard candidate.status == "scheduled", candidate.plannedStart > .now,
                  candidate.plannedStart >= start else { return false }
            switch scope {
            case .event: return candidate === event
            case .group:
                guard let group, !group.isEmpty else { return candidate === event }
                return candidate.groupID == group &&
                    calendar.isDate(candidate.plannedStart, inSameDayAs: start)
            case .day:
                return calendar.isDate(candidate.plannedStart, inSameDayAs: start)
            }
        }.sorted { $0.plannedStart < $1.plannedStart }
    }

    // MARK: - Text

    private func shiftText(
        _ minutes: Int
    ) -> String {
        if minutes > 0 {
            return "+\(minutes) мин"
        }

        return "\(minutes) мин"
    }

    // MARK: - Apply

    private func applyShift() {
        guard let stage = event.stage else {
            return
        }

        guard shiftMinutes != 0, !eventsToShift.isEmpty else { return }

        for scheduleEvent in eventsToShift {
            scheduleEvent.plannedStart =
                Calendar.current.date(
                    byAdding: .minute,
                    value: shiftMinutes,
                    to: scheduleEvent.plannedStart
                ) ?? scheduleEvent.plannedStart
        }

        do {
            try modelContext.save()

            Task {

                // Пересобираем iPhone-уведомления
                // для всего этапа, потому что могло
                // измениться сразу много событий.

                await NotificationManager.shared
                    .rescheduleNotifications(
                        for: stage
                    )

                // Отправляем уже изменённое
                // расписание на Watch.

                PhoneWatchConnectivityManager.shared
                    .send(
                        stage: stage
                    )
            }

            dismiss()

        } catch {
            print(
                "Ошибка сдвига расписания: \(error)"
            )
        }
    }
}
