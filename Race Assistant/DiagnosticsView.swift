import SwiftUI
import SwiftData
import Combine
import UserNotifications

@MainActor
final class CarPlayDiagnostics: ObservableObject {
    static let shared = CarPlayDiagnostics()
    @Published var connected = false
    @Published var updatedAt: Date?
    @Published var stageName = ""
    @Published var role = ""
    @Published var currentTitle = ""
    @Published var nextTitle = ""
}

struct DiagnosticsView: View {
    @Query private var stages: [Stage]
    @ObservedObject private var watch = PhoneWatchConnectivityManager.shared
    @ObservedObject private var carPlay = CarPlayDiagnostics.shared
    @State private var selectedStage: Stage?
    @State private var selectingStage = false
    @State private var authorization = "Проверяется…"
    @State private var pending: [UNNotificationRequest] = []

    private var stage: Stage? {
        selectedStage ?? SchedulePresentation.workingStage(stages, now: .now)
            ?? SchedulePresentation.todayStages(stages, now: .now).first
            ?? stages.filter { $0.season?.championship != nil }.sorted { $0.startDate < $1.startDate }.first
    }
    private var events: [ScheduleEvent] {
        guard let stage, !stage.scheduleEvents.contains(where: { $0.isRace && $0.status == "red_flag" }) else { return [] }
        return stage.scheduleEvents.filter { $0.status == "scheduled" && SchedulePresentation.relevant($0, stage: stage) }
            .sorted { $0.plannedStart < $1.plannedStart }
    }
    private var requests: [UNNotificationRequest] {
        guard let stage else { return [] }
        let ids = Set(stage.scheduleEvents.map { $0.notificationID.uuidString })
        return pending.filter { request in ids.contains { request.identifier.contains($0) } }
            .sorted { triggerDate($0) < triggerDate($1) }
    }
    var body: some View {
        List {
            Section("Проверяемый этап") {
                Button { selectingStage = true } label: {
                    LabeledContent("Серия → этап", value: selectedStage.map { "\($0.season?.championship?.name ?? "") · \($0.name)" } ?? "Автоматически")
                }
                if let stage {
                    LabeledContent("Этап", value: stage.name)
                    LabeledContent("Участие", value: stage.participationTitle)
                    LabeledContent("Конфигурация", value: stage.effectiveConfiguration?.name ?? "Не указана")
                    LabeledContent("Событий всего", value: "\(stage.scheduleEvents.count)")
                    LabeledContent("Подходят моему участию", value: "\(events.count)")
                    if stage.scheduleEvents.contains(where: { $0.isRace && $0.status == "red_flag" }) {
                        Text("Красный флаг: расписание Watch и напоминания этапа приостановлены.").foregroundStyle(.red)
                    }
                }
            }
            Section("Что ожидается по участию") {
                if let current = SchedulePresentation.current(events, now: .now) {
                    LabeledContent("Сейчас", value: current.title)
                } else { Text("Текущей активности нет") }
                ForEach(Array(events.filter { $0.plannedStart > .now }.prefix(3))) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(RaceClock.time(event.plannedStart)) · \(event.title)")
                        Text(event.plannedStart.formatted(.dateTime.day().month())).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("У официального лица показываются события с его ролью. Для SC дополнительно доступны гонки. Строки без ролей исключены. У спортсмена показываются выбранные классы, у зрителя — всё расписание.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Watch: фактический обмен") {
                LabeledContent("Часы сопряжены", value: watch.isPaired ? "Да" : "Нет")
                LabeledContent("Приложение установлено", value: watch.isWatchAppInstalled ? "Да" : "Нет")
                LabeledContent("Доступны прямо сейчас", value: watch.isReachable ? "Да" : "Нет")
                LabeledContent("Последняя отправка", value: dateText(watch.lastSentAt))
                LabeledContent("Подтверждение часов", value: dateText(watch.lastAcknowledgedAt))
                LabeledContent("Ожидаем подтверждение", value: watch.isWaitingForWatchSync ? "Да" : "Нет")
                LabeledContent("Watch принял уведомления", value: watch.watchNotificationsActive ? "Да" : "Нет")
                if let count = watch.watchPendingNotificationCount { LabeledContent("Уведомлений на Watch", value: "\(count)") }
                if let sent = watch.lastSentSchedule {
                    LabeledContent("Отправленный этап", value: sent.stageName)
                    LabeledContent("Отправленная роль", value: sent.myRole.isEmpty ? "Не выбрана" : sent.myRole)
                    LabeledContent("Отправлено событий", value: "\(sent.events.count)")
                    ForEach(Array(sent.events.filter { $0.start > .now }.prefix(3))) { event in
                        Text("\(RaceClock.time(event.start)) · \(event.title)").font(.caption)
                    }
                }
                if let error = watch.lastSyncError { Text(error).foregroundStyle(.red) }
                Text("Нет прямой связи — не обязательно ошибка: передача может произойти в фоне. Эти сведения относятся к обмену после запуска iPhone-приложения.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("CarPlay: последний показ") {
                LabeledContent("Подключён", value: carPlay.connected ? "Да" : "Нет")
                LabeledContent("Обновлён", value: dateText(carPlay.updatedAt))
                if carPlay.updatedAt != nil {
                    LabeledContent("Этап", value: carPlay.stageName)
                    LabeledContent("Участие", value: carPlay.role)
                    LabeledContent("Сейчас / следующее", value: carPlay.currentTitle)
                    LabeledContent("Затем", value: carPlay.nextTitle)
                }
            }
            Section("Уведомления iPhone") {
                LabeledContent("Разрешение системы", value: authorization)
                if let stage {
                    LabeledContent("Режим этапа", value: stage.notificationMode.title)
                    let offsets = [(10, stage.stageRemind10Minutes), (5, stage.stageRemind5Minutes), (1, stage.stageRemind1Minute)]
                        .filter { $0.1 }.map { String($0.0) }.joined(separator: ", ")
                    LabeledContent("За сколько минут", value: offsets.isEmpty ? "Интервалы не выбраны" : offsets)
                }
                LabeledContent("В очереди для этапа", value: "\(requests.count)")
                if watch.watchNotificationsActive {
                    Text("Напоминания переданы Watch. Очередь iPhone для этих событий может быть пустой.").font(.caption)
                }
                ForEach(requests, id: \.identifier) { request in
                    VStack(alignment: .leading) {
                        Text(request.content.title)
                        Text(request.content.body).font(.caption)
                        Text(triggerDate(request).formatted(.dateTime.day().month().hour().minute())).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Обновить сведения", systemImage: "arrow.clockwise") { Task { await refresh() } }
                Button("Повторить синхронизацию и напоминания") {
                    if let stage { watch.send(stage: stage) }
                    else { watch.sendPreferredStage() }
                    Task { await refresh() }
                }
            } footer: {
                Text("Отправляется рабочий этап, выбранный приложением. Очередь системных уведомлений не гарантирует звук: проверьте режим фокусирования и настройки часов.")
            }
        }
        .navigationTitle("Диагностика")
        .sheet(isPresented: $selectingStage) { StageSelectionView { selectedStage = $0 } }
        .task { await refresh() }
        .onChange(of: selectedStage?.persistentModelID) { _, _ in Task { await refresh() } }
    }
    private func refresh() async {
        watch.refreshStatus()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: authorization = "Разрешены"
        case .denied: authorization = "Запрещены"
        case .notDetermined: authorization = "Не запрошено"
        case .provisional: authorization = "Тихие уведомления"
        case .ephemeral: authorization = "Временное разрешение"
        @unknown default: authorization = "Неизвестно"
        }
        pending = await center.pendingNotificationRequests()
    }
    private func triggerDate(_ request: UNNotificationRequest) -> Date {
        (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
    }
    private func dateText(_ date: Date?) -> String {
        date?.formatted(.dateTime.day().month().hour().minute().second()) ?? "Нет данных"
    }
}
