import SwiftUI
import SwiftData

struct SafetyCarPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var storedPeriods: [SafetyCarPeriod]
    let stage: Stage
    @State private var selectedEvent: ScheduleEvent?
    @State private var showingAddPeriod = false
    @State private var periodToEdit: SafetyCarPeriod?
    @State private var errorMessage: String?

    private var races: [ScheduleEvent] {
        stage.scheduleEvents.filter { $0.isRace }.sorted { $0.plannedStart < $1.plannedStart }
    }
    private var periods: [SafetyCarPeriod] { storedPeriods.filter { $0.scheduleEvent?.stage === stage } }
    private var selectedPeriods: [SafetyCarPeriod] {
        guard let selectedEvent else { return [] }
        return periods.filter { $0.scheduleEvent === selectedEvent }.sorted {
            ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast)
        }
    }
    private var activePeriod: SafetyCarPeriod? { periods.first { $0.isActive } }
    private var pastRaceSelected: Bool {
        guard let selectedEvent else { return false }
        let start = selectedEvent.actualStart ?? selectedEvent.plannedStart
        let end = start.addingTimeInterval(TimeInterval(selectedEvent.actualDuration ?? selectedEvent.plannedDuration) * 60)
        return selectedEvent.status == "finished" || end <= .now
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                List {
                    Section("Гонка") {
                        Picker("Гонка", selection: $selectedEvent) {
                            Text("Выберите гонку").tag(nil as ScheduleEvent?)
                            ForEach(races) { event in
                                Text(SchedulePresentation.raceLabel(event)).tag(event as ScheduleEvent?)
                            }
                        }
                    }
                    Section {
                        if let period = activePeriod {
                            VStack(spacing: 14) {
                                Text("SAFETY CAR АКТИВЕН").font(.headline).foregroundStyle(.orange)
                                if let event = period.scheduleEvent {
                                    Text(SchedulePresentation.raceLabel(event)).font(.subheadline)
                                }
                                Text("\(period.lapCount)").font(.system(size: 64, weight: .bold, design: .rounded))
                                Text("КРУГОВ ПОД SC").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button { changeLaps(period, by: -1) } label: {
                                        Image(systemName: "minus").frame(maxWidth: .infinity, minHeight: 50)
                                    }.buttonStyle(.bordered).disabled(period.lapCount == 0)
                                    Button { changeLaps(period, by: 1) } label: {
                                        Text("+ КРУГ").frame(maxWidth: .infinity, minHeight: 50)
                                    }.buttonStyle(.borderedProminent)
                                }
                                Button("ЗАВЕРШИТЬ SC", role: .destructive) {
                                    period.isRunning = false
                                    if save() { periodToEdit = period }
                                }.buttonStyle(.bordered)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                        } else {
                            Button {
                                if pastRaceSelected { showingAddPeriod = true } else { start() }
                            } label: {
                                Text(pastRaceSelected ? "ДОБАВИТЬ ВЫЕЗД SC" : "НАЧАТЬ SC")
                                    .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60)
                            }.buttonStyle(.borderedProminent).disabled(selectedEvent == nil)
                        }
                    }
                    if let selectedEvent {
                        Section("Статистика гонки") {
                            NavigationLink {
                                SafetyCarStatisticsView(stage: stage, event: selectedEvent)
                            } label: {
                                LabeledContent("Выездов Safety Car", value: "\(selectedPeriods.count)")
                            }
                            LabeledContent("Кругов под Safety Car", value: "\(selectedPeriods.reduce(0) { $0 + $1.lapCount })")
                        }
                        Section("История гонки") {
                            ForEach(selectedPeriods) { period in
                                Button { periodToEdit = period } label: { SafetyCarRecordRow(period: period) }
                                    .buttonStyle(.plain)
                            }.onDelete { offsets in
                                let snapshot = selectedPeriods
                                for index in offsets { modelContext.delete(snapshot[index]) }
                                _ = save()
                            }
                        }
                    }
                    Section("Итого за этап") {
                        NavigationLink {
                            SafetyCarStatisticsView(stage: stage)
                        } label: {
                            LabeledContent("Выездов Safety Car", value: "\(periods.count)")
                        }
                        LabeledContent("Кругов под Safety Car", value: "\(periods.reduce(0) { $0 + $1.lapCount })")
                    }
                }
            }
            .navigationTitle("Safety Car")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedEvent == nil {
                    selectedEvent = activePeriod?.scheduleEvent ?? SchedulePresentation.current(races, now: .now)
                        ?? races.last { $0.plannedStart < .now } ?? races.first
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingAddPeriod = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            .sheet(isPresented: $showingAddPeriod) {
                EditSafetyCarPeriodView(stage: stage, selectedEvent: selectedEvent)
            }
            .sheet(item: $periodToEdit) { EditSafetyCarPeriodView(stage: stage, period: $0) }
            .alert("Не удалось сохранить", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        }
    }

    private func start() {
        guard let selectedEvent, activePeriod == nil else { return }
        let period = SafetyCarPeriod(startedAt: .now, scheduleEvent: selectedEvent)
        period.isRunning = true
        modelContext.insert(period)
        _ = save()
    }
    private func changeLaps(_ period: SafetyCarPeriod, by delta: Int) {
        period.lapCount = max(0, period.lapCount + delta)
        _ = save()
    }
    @discardableResult private func save() -> Bool {
        do { try modelContext.save(); return true }
        catch { modelContext.rollback(); errorMessage = error.localizedDescription; return false }
    }
}
