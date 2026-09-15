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
    @State private var startedAt: Date
    @State private var errorMessage: String?

    private var raceEvents: [ScheduleEvent] {
        stage.scheduleEvents.filter { $0.isRace }.sorted { $0.plannedStart < $1.plannedStart }
    }

    init(stage: Stage, period: SafetyCarPeriod? = nil, selectedEvent: ScheduleEvent? = nil) {
        self.stage = stage
        self.period = period
        let events = stage.scheduleEvents.filter { $0.isRace }.sorted { $0.plannedStart < $1.plannedStart }
        let event = period?.scheduleEvent ?? selectedEvent ?? SchedulePresentation.current(events, now: .now)
        _selectedEvent = State(initialValue: event)
        _lapCount = State(initialValue: period?.lapCount ?? 0)
        _notes = State(initialValue: period?.notes ?? "")
        _startedAt = State(initialValue: period?.startedAt ?? Self.defaultStart(event))
    }

    private static func defaultStart(_ event: ScheduleEvent?) -> Date {
        guard let event else { return .now }
        let start = event.actualStart ?? event.plannedStart
        let end = start.addingTimeInterval(TimeInterval(event.actualDuration ?? event.plannedDuration) * 60)
        return event.status == "finished" || end <= .now ? start : .now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Гонка") {
                    Picker("Гонка", selection: $selectedEvent) {
                        Text("Выберите гонку").tag(nil as ScheduleEvent?)
                        ForEach(raceEvents) { event in
                            Text(SchedulePresentation.raceLabel(event)).tag(event as ScheduleEvent?)
                        }
                    }
                    .onChange(of: selectedEvent?.persistentModelID) { _, _ in
                        // Selecting a past race pre-fills its start, but it remains editable.
                        startedAt = Self.defaultStart(selectedEvent)
                    }
                }
                Section("Круги") {
                    Stepper("Кругов под SC: \(lapCount)", value: $lapCount, in: 0...999)
                }
                Section("Начало SC") {
                    DatePicker("Начало", selection: $startedAt, displayedComponents: [.date, .hourAndMinute])
                }
                Section("Причина / заметки") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
            }
            .navigationTitle(period == nil ? "Добавить выезд SC" : "Редактирование SC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(selectedEvent == nil)
                }
            }
            .alert("Не удалось сохранить", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let selectedEvent else { return }
        let target = period ?? SafetyCarPeriod()
        if period == nil { modelContext.insert(target) }
        target.scheduleEvent = selectedEvent
        target.lapCount = lapCount
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.startedAt = startedAt
        // Manual entry is a completed record, never a live deployment.
        // Historical endedAt remains untouched for compatibility with the existing store.
        if period == nil { target.isRunning = false }
        do { try modelContext.save(); dismiss() }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription }
    }
}
