import Foundation
import UserNotifications

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let categoryIdentifier =
        "RACE_ASSISTANT_EVENT"

    private let acknowledgeActionIdentifier =
        "RACE_ASSISTANT_ACKNOWLEDGE"

    private override init() {
        super.init()

        let center =
            UNUserNotificationCenter.current()

        center.delegate = self

        registerNotificationCategories()
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted =
                try await UNUserNotificationCenter
                    .current()
                    .requestAuthorization(
                        options: [
                            .alert,
                            .sound,
                            .badge
                        ]
                    )

            print(
                "iPhone notification permission: \(granted)"
            )

            if granted {
                registerNotificationCategories()
            }

        } catch {
            print(
                "Ошибка запроса разрешения уведомлений: \(error)"
            )
        }
    }

    // MARK: - Categories

    private func registerNotificationCategories() {
        let acknowledgeAction =
            UNNotificationAction(
                identifier:
                    acknowledgeActionIdentifier,
                title:
                    "ПРИНЯТО",
                options: []
            )

        let eventCategory =
            UNNotificationCategory(
                identifier:
                    categoryIdentifier,
                actions: [
                    acknowledgeAction
                ],
                intentIdentifiers: [],
                options: []
            )

        UNUserNotificationCenter.current()
            .setNotificationCategories([
                eventCategory
            ])
    }

    // MARK: - Schedule One Event

    func scheduleNotifications(
        for event: ScheduleEvent
    ) async {

        let center =
            UNUserNotificationCenter.current()

        // Всегда сначала удаляем
        // старые уведомления события.

        center.removePendingNotificationRequests(
            withIdentifiers:
                allIdentifiers(
                    for: event
                )
        )

        // Если Watch отвечает
        // за уведомления,
        // iPhone ничего не создаёт.

        if PhoneWatchConnectivityManager.shared
            .watchNotificationsActive {

            print(
                "iPhone notification skipped: Watch notifications active"
            )

            return
        }

        guard let stage =
            event.stage
        else {
            return
        }

        guard shouldNotify(
            for: event,
            stage: stage
        ) else {
            return
        }

        let offsets =
            reminderOffsets(
                for: stage
            )

        guard !offsets.isEmpty else {
            return
        }

        for minutesBefore in offsets {

            guard let notificationDate =
                Calendar.current.date(
                    byAdding: .minute,
                    value: -minutesBefore,
                    to: event.plannedStart
                )
            else {
                continue
            }

            guard notificationDate > Date()
            else {
                continue
            }

            let content =
                UNMutableNotificationContent()

            content.title =
                title(
                    minutesBefore:
                        minutesBefore
                )

            content.body =
                body(
                    for: event
                )

            content.sound =
                .default

            content.interruptionLevel =
                .timeSensitive

            content.categoryIdentifier =
                categoryIdentifier

            content.userInfo = [
                "eventID":
                    event.notificationID.uuidString,
                "minutesBefore":
                    minutesBefore
            ]

            let components =
                Calendar.current.dateComponents(
                    [
                        .year,
                        .month,
                        .day,
                        .hour,
                        .minute
                    ],
                    from: notificationDate
                )

            let trigger =
                UNCalendarNotificationTrigger(
                    dateMatching:
                        components,
                    repeats:
                        false
                )

            let request =
                UNNotificationRequest(
                    identifier:
                        identifier(
                            for: event,
                            minutesBefore:
                                minutesBefore
                        ),
                    content:
                        content,
                    trigger:
                        trigger
                )

            do {
                try await center.add(
                    request
                )

                print(
                    "iPhone notification created: \(request.identifier)"
                )

            } catch {
                print(
                    "Ошибка создания iPhone notification: \(error)"
                )
            }
        }
    }

    // MARK: - Reschedule Stage

    func rescheduleNotifications(
        for stage: Stage
    ) async {

        // Сначала полностью очищаем
        // старые уведомления этапа.

        for event in stage.scheduleEvents {
            removeNotifications(
                for: event
            )
        }

        // Режим "Не уведомлять".
        // После очистки больше
        // ничего создавать не надо.

        guard stage.notificationMode
            != .none
        else {

            print(
                "iPhone stage notifications disabled"
            )

            return
        }

        // Если Watch отвечает
        // за уведомления,
        // iPhone остаётся fallback.

        if PhoneWatchConnectivityManager.shared
            .watchNotificationsActive {

            print(
                "iPhone stage notifications removed: Watch owns notifications"
            )

            return
        }

        let offsets =
            reminderOffsets(
                for: stage
            )

        guard !offsets.isEmpty
        else {

            print(
                "iPhone stage notifications disabled: no reminder intervals selected"
            )

            return
        }

        let futureEvents =
            stage.scheduleEvents
                .filter {
                    $0.plannedStart > Date()
                }
                .sorted {
                    $0.plannedStart <
                    $1.plannedStart
                }

        for event in futureEvents {
            await scheduleNotifications(
                for: event
            )
        }

        print(
            "iPhone notifications rescheduled as fallback"
        )
    }

    // MARK: - Notification Filtering

    private func shouldNotify(
        for event: ScheduleEvent,
        stage: Stage
    ) -> Bool {

        switch stage.notificationMode {

        // Ничего не уведомляем.

        case .none:
            return false

        // Любая строка расписания.

        case .all:
            return true

        // Только строки,
        // в которых явно указана
        // моя роль.

        case .myRole:

            guard let myRole =
                stage.myRole
            else {
                return false
            }

            // Пустой список ролей
            // НЕ считаем общим событием.
            //
            // В импортированном расписании
            // это может означать,
            // что роли ещё просто
            // не заполнены.

            guard
                !event.eventRoles.isEmpty
            else {
                return false
            }

            return event.eventRoles
                .contains { eventRole in

                    guard let role =
                        eventRole.role
                    else {
                        return false
                    }

                    return role === myRole
                }
        }
    }

    // MARK: - Remove

    func removeNotifications(
        for event: ScheduleEvent
    ) {

        let center =
            UNUserNotificationCenter.current()

        let identifiers =
            allIdentifiers(
                for: event
            )

        center.removePendingNotificationRequests(
            withIdentifiers:
                identifiers
        )

        center.removeDeliveredNotifications(
            withIdentifiers:
                identifiers
        )
    }

    // MARK: - Stage Reminder Offsets

    private func reminderOffsets(
        for stage: Stage
    ) -> [Int] {

        var offsets: [Int] = []

        if stage.stageRemind10Minutes {
            offsets.append(10)
        }

        if stage.stageRemind5Minutes {
            offsets.append(5)
        }

        if stage.stageRemind1Minute {
            offsets.append(1)
        }

        return offsets
    }

    // MARK: - Identifiers

    private func identifier(
        for event: ScheduleEvent,
        minutesBefore: Int
    ) -> String {

        return
            "raceassistant-\(event.notificationID.uuidString)-\(minutesBefore)"
    }

    private func allIdentifiers(
        for event: ScheduleEvent
    ) -> [String] {

        [10, 5, 1].map {
            identifier(
                for: event,
                minutesBefore: $0
            )
        }
    }

    // MARK: - Notification Title

    private func title(
        minutesBefore: Int
    ) -> String {

        switch minutesBefore {

        case 1:
            return "Через 1 минуту"

        case 5:
            return "Через 5 минут"

        case 10:
            return "Через 10 минут"

        default:
            return "Предстоящее событие"
        }
    }

    // MARK: - Notification Body

    private func body(
        for event: ScheduleEvent
    ) -> String {

        var parts: [String] = []

        parts.append(
            event.title
        )

        let classes =
            event.eventClasses
                .compactMap {
                    $0.raceClass
                }
                .map {
                    $0.shortName.isEmpty
                        ? $0.name
                        : $0.shortName
                }
                .sorted()

        if !classes.isEmpty {
            parts.append(
                classes.joined(
                    separator: ", "
                )
            )
        }

        return parts.joined(
            separator: " · "
        )
    }
}


// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager:
    UNUserNotificationCenterDelegate {

    // MARK: Foreground Notification

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (
                UNNotificationPresentationOptions
            ) -> Void
    ) {

        completionHandler([
            .banner,
            .list,
            .sound
        ])
    }

    // MARK: Notification Action

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler:
            @escaping () -> Void
    ) {

        switch response.actionIdentifier {

        case acknowledgeActionIdentifier:

            let identifier =
                response.notification
                    .request
                    .identifier

            center.removeDeliveredNotifications(
                withIdentifiers: [
                    identifier
                ]
            )

            print(
                "Notification acknowledged: \(identifier)"
            )

        case UNNotificationDefaultActionIdentifier:

            print(
                "Notification opened"
            )

        default:
            break
        }

        completionHandler()
    }
}
