import SwiftUI
import SwiftData

struct ShiftScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: ScheduleEvent

    @State private var shiftMinutes = 10
    @State private var shiftFollowingEvents = true

    private let quickOptions = [
        -10,
        -5,
        5,
        10,
        15,
        30
    ]

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Сдвиг

                Section("Сдвиг") {
                    Picker(
                        "Минут",
                        selection: $shiftMinutes
                    ) {
                        ForEach(
                            quickOptions,
                            id: \.self
                        ) { minutes in
                            Text(
                                shiftText(minutes)
                            )
                            .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                // MARK: - Применить

                Section("Применить") {
                    Toggle(
                        "Сдвинуть последующие события",
                        isOn: $shiftFollowingEvents
                    )

                    if shiftFollowingEvents {
                        Text(
                            "Будут сдвинуты выбранное событие и все последующие события этапа."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Будет изменено только выбранное событие."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
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
                        shiftMinutes == 0
                    )
                }
            }
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

        let originalStart =
            event.plannedStart

        let eventsToShift: [ScheduleEvent]

        if shiftFollowingEvents {

            eventsToShift =
                stage.scheduleEvents
                    .filter {
                        $0.plannedStart >= originalStart
                    }
                    .sorted {
                        $0.plannedStart < $1.plannedStart
                    }

        } else {

            eventsToShift = [
                event
            ]
        }

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
