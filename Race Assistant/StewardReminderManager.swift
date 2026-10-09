import Foundation
import SwiftData
import UserNotifications

/// Own namespace: never cancel schedule reminders or delegate notifications away from NotificationManager.
@MainActor
enum StewardReminderManager {
    private static let prefix = "RA_STEWARD_"
    private static var synchronizing = false
    private static var refreshNeeded = false
    static func synchronize(_ context: ModelContext) async -> String {
        refreshNeeded = true
        guard !synchronizing else { return "Обновление напоминаний…" }
        synchronizing = true
        defer { synchronizing = false }
        var message = ""
        while refreshNeeded {
            refreshNeeded = false
            message = await rebuild(context)
        }
        return message
    }
    private static func rebuild(_ context: ModelContext) async -> String {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral else {
            return "Уведомления не разрешены. Задачи и сроки сохранены в журнале."
        }
        let all = (try? context.fetch(FetchDescriptor<StewardIncidentTask>())) ?? []
        let tasks = all.filter { $0.completedAt == nil && $0.incident?.stage != nil && ($0.dueAt ?? .distantPast) > .now }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let budget = max(0, min(32, 62 - pending.filter { !$0.identifier.hasPrefix(prefix) }.count))
        var count = 0
        for task in tasks.prefix(budget) {
            guard let due = task.dueAt, let incident = task.incident else { break }
            let content = UNMutableNotificationContent()
            content.title = "КСК · \(task.title)"
            content.body = "\(incident.stage?.name ?? "Этап") · \(incident.title)"
            content.sound = .default
            content.threadIdentifier = "steward-\(incident.incidentID.uuidString)"
            content.userInfo = ["stewardIncidentID": incident.incidentID.uuidString]
            let request = UNNotificationRequest(identifier: prefix + task.taskID.uuidString, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSinceNow), repeats: false))
            do { try await center.add(request); count += 1 }
            catch { return "Не удалось поставить напоминание: \(error.localizedDescription)" }
        }
        if tasks.count > count { return "Запланировано \(count) из \(tasks.count). Остальные сроки сохранены; список обновляется при открытии приложения." }
        return count == 0 ? "Задачи со сроком напоминают на iPhone. Уведомления разрешены." : "Запланировано напоминаний: \(count)"
    }
}
