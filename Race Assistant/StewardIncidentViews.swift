import SwiftUI
import SwiftData
import UIKit

struct StewardIncidentListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StewardIncident.occurredAt, order: .reverse) private var stored: [StewardIncident]
    let stage: Stage
    @State private var adding = false
    @State private var search = ""
    @State private var filter = "open"
    @State private var reminderStatus = ""
    @State private var errorText: String?
    @State private var deleting: StewardIncident?
    private var incidents: [StewardIncident] {
        stored.filter { $0.stage === stage && (filter == "all" || $0.status != .decided || !$0.openTasks.isEmpty) &&
            (search.isEmpty || "\($0.title) \($0.driverNumbers) \($0.incidentDescription) \($0.verdict)".localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Section {
                Picker("Показать", selection: $filter) {
                    Text("В работе").tag("open")
                    Text("Все").tag("all")
                }.pickerStyle(.segmented)
            } footer: { Text("Личный журнал на этом iPhone. Записи не публикуются и сохраняются при обновлении расписания.") }
            if incidents.isEmpty {
                Section { ContentUnavailableView("Инцидентов нет", systemImage: "checklist", description: Text("Создайте инцидент кнопкой +. Решения доступны в разделе «Все».")) }
            }
            ForEach(incidents) { incident in
                NavigationLink { StewardIncidentDetailView(incident: incident) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(incident.title).font(.headline)
                        HStack {
                            Text(incident.occurredAt, format: .dateTime.day().month().hour().minute())
                            Spacer()
                            Text(incident.status.title).foregroundStyle(incident.status == .decided ? Color.green : Color.orange)
                        }.font(.caption)
                        if !incident.driverNumbers.isEmpty { Text("Спортсмены: \(incident.driverNumbers)").font(.subheadline) }
                        if let value = incident.raceClass { Text(value.shortName.isEmpty ? value.name : value.shortName).font(.caption).foregroundStyle(.secondary) }
                        if !incident.openTasks.isEmpty { Text("Открытых задач: \(incident.openTasks.count)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                .swipeActions {
                    Button(role: .destructive) { deleting = incident } label: { Label("Удалить", systemImage: "trash") }
                }
            }
            Section("Напоминания") {
                Text(reminderStatus).font(.footnote).foregroundStyle(.secondary)
                Button("Проверить разрешение уведомлений") {
                    Task {
                        await NotificationManager.shared.requestPermission()
                        reminderStatus = await StewardReminderManager.synchronize(context)
                    }
                }
                Button("Открыть настройки iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .navigationTitle("Журнал КСК")
        .searchable(text: $search, prompt: "Описание, номер, решение")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } }
        }
        .sheet(isPresented: $adding, onDismiss: {
            PhoneWatchConnectivityManager.shared.send(stage: stage)
            Task { reminderStatus = await StewardReminderManager.synchronize(context) }
        }) {
            StewardIncidentEditor(stage: stage, onCancel: { adding = false })
        }
        .task {
            PhoneWatchConnectivityManager.shared.send(stage: stage)
            reminderStatus = await StewardReminderManager.synchronize(context)
        }
        .onChange(of: stored.count) { _, _ in Task { reminderStatus = await StewardReminderManager.synchronize(context) } }
        .confirmationDialog("Удалить инцидент и его задачи?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                guard let deleting else { return }
                context.delete(deleting)
                do {
                    try context.save(); self.deleting = nil
                    PhoneWatchConnectivityManager.shared.send(stage: stage)
                    Task { reminderStatus = await StewardReminderManager.synchronize(context) }
                }
                catch { context.rollback(); errorText = error.localizedDescription }
            }
        }
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
    }
}

struct StewardIncidentEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let stage: Stage
    var incident: StewardIncident?
    var onCancel: (() -> Void)?
    @State private var title: String
    @State private var description: String
    @State private var occurredAt: Date
    @State private var numbers: String
    @State private var selectedClassID: PersistentIdentifier?
    @State private var errorText: String?
    init(stage: Stage, incident: StewardIncident? = nil, onCancel: (() -> Void)? = nil) {
        self.stage = stage; self.incident = incident
        self.onCancel = onCancel
        _title = State(initialValue: incident?.title ?? "")
        _description = State(initialValue: incident?.incidentDescription ?? "")
        _occurredAt = State(initialValue: incident?.occurredAt ?? .now)
        _numbers = State(initialValue: incident?.driverNumbers ?? "")
        _selectedClassID = State(initialValue: incident?.raceClass?.persistentModelID)
    }
    private var classes: [RaceClass] {
        var values = stage.availableClasses.filter { $0.active }
        if let raceClass = incident?.raceClass, !values.contains(where: { $0 === raceClass }) { values.append(raceClass) }
        return values.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Инцидент") {
                    TextField("Краткое название", text: $title)
                    DatePicker("Время инцидента", selection: $occurredAt)
                    TextField("Описание: что произошло", text: $description, axis: .vertical).lineLimit(3...8)
                }
                Section("Участники · необязательно") {
                    Picker("Класс", selection: $selectedClassID) {
                        Text("Не указан").tag(nil as PersistentIdentifier?)
                        ForEach(classes) { value in
                            Text(value.name).tag(value.persistentModelID as PersistentIdentifier?)
                        }
                    }
                    if classes.isEmpty {
                        Text("Добавьте классы в разделе «Классы этапа». Классы из расписания подставляются автоматически.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Номера спортсменов, например 7, 23", text: $numbers)
                }
                if incident == nil {
                    Section { Text("Статус «Подан». Задачи «Взять в рассмотрение» и «Вынести решение» появятся автоматически.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(incident == nil ? "Новый инцидент" : "Изменить инцидент")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { if let onCancel { onCancel() } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
        }
    }
    private func save() {
        let value = incident ?? StewardIncident(title: title, occurredAt: occurredAt, stage: stage)
        if incident == nil { context.insert(value); if !stage.stewardIncidents.contains(where: { $0 === value }) { stage.stewardIncidents.append(value) } }
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.incidentDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        value.occurredAt = occurredAt; value.driverNumbers = numbers.trimmingCharacters(in: .whitespacesAndNewlines)
        value.raceClass = classes.first { $0.persistentModelID == selectedClassID }
        value.makeRequiredTasks()
        do {
            try context.save()
            PhoneWatchConnectivityManager.shared.send(stage: stage)
            let savedContext = context
            Task { _ = await StewardReminderManager.synchronize(savedContext) }
            dismiss()
        }
        catch { context.rollback(); errorText = error.localizedDescription }
    }
}

struct StewardIncidentDetailView: View {
    @Environment(\.modelContext) private var context
    let incident: StewardIncident
    @State private var editing = false
    @State private var addingTask = false
    @State private var taskToEdit: StewardIncidentTask?
    @State private var deciding = false
    @State private var reopening = false
    @State private var errorText: String?
    private var orderedTasks: [StewardIncidentTask] {
        incident.tasks.sorted {
            let a = $0.kind == "review" ? 0 : ($0.kind == "decision" ? 1 : 2)
            let b = $1.kind == "review" ? 0 : ($1.kind == "decision" ? 1 : 2)
            return a != b ? a < b : $0.createdAt < $1.createdAt
        }
    }
    var body: some View {
        List {
            Section {
                LabeledContent("Статус", value: incident.status.title)
                Text(incident.title).font(.headline)
                LabeledContent("Время инцидента") { Text(incident.occurredAt, format: .dateTime.day().month().hour().minute()) }
                if !incident.incidentDescription.isEmpty { Text(incident.incidentDescription).textSelection(.enabled) }
                if let value = incident.raceClass { LabeledContent("Класс", value: value.name) }
                if !incident.driverNumbers.isEmpty { LabeledContent("Спортсмены", value: incident.driverNumbers) }
            }
            Section("Задачи") {
                ForEach(orderedTasks) { task in
                    HStack(alignment: .top, spacing: 12) {
                        Button { complete(task) } label: {
                            Image(systemName: task.completedAt == nil ? "circle" : "checkmark.circle.fill")
                                .font(.title2).foregroundStyle(task.completedAt == nil ? Color.secondary : Color.green)
                        }
                        .buttonStyle(.borderless)
                        .disabled(task.kind == "review" && task.completedAt != nil || task.kind == "decision" && incident.status != .reviewing)
                        Button { taskToEdit = task } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).strikethrough(task.completedAt != nil)
                                if let due = task.dueAt {
                                    Text(due, format: .dateTime.day().month().hour().minute())
                                        .font(.caption).foregroundStyle(task.completedAt == nil && due < .now ? Color.red : Color.secondary)
                                }
                                if task.kind == "decision", incident.status == .submitted { Text("Сначала возьмите в рассмотрение").font(.caption).foregroundStyle(.secondary) }
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 3)
                    .swipeActions {
                        if !task.isRequired {
                            Button(role: .destructive) { context.delete(task); persist() } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }
                Button("Добавить задачу", systemImage: "plus") { addingTask = true }
            }
            if incident.status == .decided {
                Section("Решение") {
                    Text(incident.outcome.title).font(.headline)
                    Text(incident.verdict).textSelection(.enabled)
                    if let decided = incident.decidedAt { Text(decided, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                    ShareLink(item: summary) { Label("Поделиться сводкой", systemImage: "square.and.arrow.up") }
                    Button("Вернуть в рассмотрение") { reopening = true }
                }
            } else if incident.status == .reviewing {
                Section { Button("Вынести решение", systemImage: "checkmark.seal") { deciding = true } }
            }
        }
        .navigationTitle("Инцидент КСК")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Изменить") { editing = true } } }
        .sheet(isPresented: $editing) {
            if let stage = incident.stage { StewardIncidentEditor(stage: stage, incident: incident) }
        }
        .sheet(isPresented: $addingTask) { StewardTaskEditor(incident: incident) }
        .sheet(item: $taskToEdit) { StewardTaskEditor(incident: incident, task: $0) }
        .sheet(isPresented: $deciding) { StewardDecisionEditor(incident: incident) }
        .confirmationDialog("Вернуть инцидент в рассмотрение?", isPresented: $reopening, titleVisibility: .visible) {
            Button("Вернуть в рассмотрение") { incident.reopenReview(); persist() }
        } message: { Text("Прежнее решение сохранится как черновик. Задача «Вынести решение» снова станет открытой.") }
        .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
    }
    private func complete(_ task: StewardIncidentTask) {
        switch task.kind {
        case "review": incident.startReview(); persist()
        case "decision": if incident.status == .reviewing { deciding = true }
        default: task.completedAt = task.completedAt == nil ? .now : nil; persist()
        }
    }
    private func persist() {
        do {
            try context.save()
            if let stage = incident.stage { PhoneWatchConnectivityManager.shared.send(stage: stage) }
            Task { _ = await StewardReminderManager.synchronize(context) }
        }
        catch { context.rollback(); errorText = error.localizedDescription }
    }
    private var summary: String {
        let time = incident.occurredAt.formatted(date: .numeric, time: .shortened)
        return "\(incident.stage?.name ?? "Этап")\nИнцидент: \(incident.title)\nВремя: \(time)\nКласс: \(incident.raceClass?.name ?? "Не указан")\nСпортсмены: \(incident.driverNumbers.isEmpty ? "Не указаны" : incident.driverNumbers)\n\(incident.incidentDescription)\nРешение: \(incident.outcome.title)\n\(incident.verdict)"
    }
}

struct StewardTaskEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let incident: StewardIncident
    var task: StewardIncidentTask?
    @State private var title: String
    @State private var hasDeadline: Bool
    @State private var due: Date
    @State private var errorText: String?
    init(incident: StewardIncident, task: StewardIncidentTask? = nil) {
        self.incident = incident; self.task = task
        _title = State(initialValue: task?.title ?? "")
        _hasDeadline = State(initialValue: task?.dueAt != nil)
        _due = State(initialValue: task?.dueAt ?? .now.addingTimeInterval(900))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название задачи", text: $title).disabled(task?.isRequired == true)
                    Toggle("Напомнить в указанное время", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("Срок", selection: $due) }
                } footer: { Text("Без срока задача остаётся в списке. Просроченная задача выделяется красным. Напоминание приходит на этот iPhone; для прошедшего срока уведомление не создаётся.") }
            }
            .navigationTitle(task == nil ? "Новая задача" : "Задача")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
        }
    }
    private func save() {
        let value = task ?? StewardIncidentTask(title: title, incident: incident)
        if task == nil { context.insert(value); if !incident.tasks.contains(where: { $0 === value }) { incident.tasks.append(value) } }
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.dueAt = hasDeadline ? due : nil
        do {
            try context.save()
            if let stage = incident.stage { PhoneWatchConnectivityManager.shared.send(stage: stage) }
            let requestPermission = hasDeadline
            let savedContext = context
            Task {
                if requestPermission { await NotificationManager.shared.requestPermission() }
                _ = await StewardReminderManager.synchronize(savedContext)
            }
            dismiss()
        } catch { context.rollback(); errorText = error.localizedDescription }
    }
}

struct StewardDecisionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let incident: StewardIncident
    @State private var verdict: String
    @State private var outcome: StewardOutcome
    @State private var errorText: String?
    init(incident: StewardIncident) {
        self.incident = incident
        _verdict = State(initialValue: incident.verdict)
        _outcome = State(initialValue: incident.outcome)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Вердикт", selection: $outcome) { ForEach(StewardOutcome.allCases) { Text($0.title).tag($0) } }
                    TextField("Общее решение: кому и какое наказание, либо почему без наказания", text: $verdict, axis: .vertical).lineLimit(5...12)
                } header: {
                    Text("Итог рассмотрения")
                } footer: {
                    Text("Сохранение решения завершает задачу «Вынести решение» и меняет статус инцидента. Дополнительные задачи остаются открытыми до их выполнения.")
                }
            }
            .navigationTitle("Вынести решение")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить решение", action: save).disabled(verdict.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || incident.status != .reviewing) }
            }
            .alert("Не удалось сохранить", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
        }
    }
    private func save() {
        guard incident.decide(text: verdict, outcome: outcome) else { return }
        do {
            try context.save()
            if let stage = incident.stage { PhoneWatchConnectivityManager.shared.send(stage: stage) }
            let savedContext = context
            Task { _ = await StewardReminderManager.synchronize(savedContext) }
            dismiss()
        }
        catch { context.rollback(); errorText = error.localizedDescription }
    }
}
