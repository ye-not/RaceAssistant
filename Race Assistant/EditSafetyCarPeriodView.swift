import SwiftUI
import SwiftData

struct EditSafetyCarPeriodView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let stage: Stage
    let period: SafetyCarPeriod?

    @State private var selectedEvent: ScheduleEvent?
    @State private var lapCount: Int
    @State private var notes: String

    @State private var hasStartTime: Bool
    @State private var startedAt: Date

    @State private var hasEndTime: Bool
    @State private var endedAt: Date

    private var raceEvents: [ScheduleEvent] {
        stage.scheduleEvents
            .filter { $0.isRace }
            .sorted {
                $0.plannedStart
                    < $1.plannedStart
            }
    }

    init(
        stage: Stage,
        period: SafetyCarPeriod? = nil
    ) {
        self.stage = stage
        self.period = period

        let now = Date()

        let currentRace =
            stage.scheduleEvents
                .filter { $0.isRace }
                .sorted {
                    $0.plannedStart
                        < $1.plannedStart
                }
                .first { event in

                    let start =
                        event.actualStart
                        ?? event.plannedStart

                    let duration =
                        event.actualDuration
                        ?? event.plannedDuration

                    let end =
                        start.addingTimeInterval(
                            TimeInterval(
                                duration * 60
                            )
                        )

                    return now >= start
                        && now < end
                }

        _selectedEvent = State(
            initialValue:
                period?.scheduleEvent
                ?? currentRace
        )

        _lapCount = State(
            initialValue:
                period?.lapCount
                ?? 0
        )

        _notes = State(
            initialValue:
                period?.notes
                ?? ""
        )

        _startedAt = State(
            initialValue:
                period?.startedAt
                ?? now
        )

        _hasStartTime = State(
            initialValue:
                period?.startedAt
                != nil
        )

        _endedAt = State(
            initialValue:
                period?.endedAt
                ?? now
        )

        _hasEndTime = State(
            initialValue:
                period?.endedAt
                != nil
        )
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Race

                Section("Заезд") {
                    Picker(
                        "Заезд",
                        selection:
                            $selectedEvent
                    ) {
                        Text(
                            "Выберите заезд"
                        )
                        .tag(
                            nil as ScheduleEvent?
                        )

                        ForEach(
                            raceEvents
                        ) { event in
                            Text(
                                eventTitle(event)
                            )
                            .tag(
                                event
                                    as ScheduleEvent?
                            )
                        }
                    }

                    if let selectedEvent {
                        let classes =
                            selectedEvent
                                .eventClasses
                                .compactMap {
                                    $0
                                        .raceClass?
                                        .name
                                }
                                .joined(
                                    separator:
                                        " · "
                                )

                        if !classes.isEmpty {
                            Text(classes)
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                        }
                    }
                }

                // MARK: - Laps

                Section("Круги") {
                    Stepper(
                        value:
                            $lapCount,
                        in: 0...999
                    ) {
                        HStack {
                            Text(
                                "Кругов под SC"
                            )

                            Spacer()

                            Text(
                                "\(lapCount)"
                            )
                            .fontWeight(
                                .semibold
                            )
                        }
                    }
                }

                // MARK: - Time

                Section("Время") {

                    Toggle(
                        "Указать начало",
                        isOn:
                            $hasStartTime
                    )

                    if hasStartTime {
                        DatePicker(
                            "Начало",
                            selection:
                                $startedAt,
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )
                    }

                    Toggle(
                        "Указать окончание",
                        isOn:
                            $hasEndTime
                    )

                    if hasEndTime {
                        DatePicker(
                            "Окончание",
                            selection:
                                $endedAt,
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )
                    }
                }

                // MARK: - Notes

                Section("Причина / заметки") {
                    TextEditor(
                        text: $notes
                    )
                    .frame(
                        minHeight: 120
                    )
                }
            }
            .navigationTitle(
                period == nil
                    ? "Новая нейтрализация"
                    : "Редактирование SC"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("Сохранить") {
                        save()
                    }
                    .disabled(
                        selectedEvent == nil
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func eventTitle(
        _ event: ScheduleEvent
    ) -> String {

        let time =
            event.plannedStart
                .formatted(
                    date: .omitted,
                    time: .shortened
                )

        return
            "\(time) · \(event.title)"
    }

    // MARK: - Save

    private func save() {
        guard let selectedEvent else {
            return
        }

        let targetPeriod:
            SafetyCarPeriod

        if let period {
            targetPeriod =
                period
        } else {
            targetPeriod =
                SafetyCarPeriod()

            modelContext.insert(
                targetPeriod
            )
        }

        targetPeriod.scheduleEvent =
            selectedEvent

        targetPeriod.lapCount =
            lapCount

        targetPeriod.notes =
            notes.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        targetPeriod.startedAt =
            hasStartTime
                ? startedAt
                : nil

        targetPeriod.endedAt =
            hasEndTime
                ? endedAt
                : nil

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print(
                "Ошибка сохранения SC: \(error)"
            )
        }
    }
}
