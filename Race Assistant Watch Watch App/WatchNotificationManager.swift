import Foundation
import UserNotifications

final class WatchNotificationManager:
    NSObject,
    UNUserNotificationCenterDelegate {

    static let shared =
        WatchNotificationManager()

    // MARK: - Identifiers

    private let categoryIdentifier =
        "RACE_ASSISTANT_WATCH_EVENT"

    private let acknowledgeActionIdentifier =
        "RACE_ASSISTANT_WATCH_ACKNOWLEDGE"

    // MARK: - Init

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
                try await
                UNUserNotificationCenter
                    .current()
                    .requestAuthorization(
                        options: [
                            .alert,
                            .sound
                        ]
                    )

            print(
                "Watch notification permission: \(granted)"
            )

            if granted {
                registerNotificationCategories()
            }

        } catch {
            print(
                "Ошибка разрешения уведомлений Watch: \(error)"
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

        UNUserNotificationCenter
            .current()
            .setNotificationCategories([
                eventCategory
            ])
    }

    // MARK: - Reschedule

    func reschedule(
        schedule: WatchScheduleData
    ) async {

        let center =
            UNUserNotificationCenter
                .current()

        // Удаляем старые Race Assistant
        // уведомления перед пересозданием.

        let pending =
            await center
                .pendingNotificationRequests()

        let raceAssistantIDs =
            pending
                .map(\.identifier)
                .filter {
                    $0.hasPrefix(
                        "raceassistant-watch-"
                    )
                }

        center
            .removePendingNotificationRequests(
                withIdentifiers:
                    raceAssistantIDs
            )

        let now =
            Date()

        var createdCount = 0

        for event in schedule.events {

            guard event.start > now
            else {
                continue
            }

            let offsets =
                reminderOffsets(
                    for: event
                )

            for minutesBefore
                in offsets {

                let created =
                    await scheduleNotification(
                        event:
                            event,
                        minutesBefore:
                            minutesBefore
                    )

                if created {
                    createdCount += 1
                }
            }
        }

        let newPending =
            await center
                .pendingNotificationRequests()

        let ourPending =
            newPending.filter {
                $0.identifier
                    .hasPrefix(
                        "raceassistant-watch-"
                    )
            }

        print(
            "Watch notifications created: \(createdCount)"
        )

        print(
            "Watch pending notifications: \(ourPending.count)"
        )
    }

    // MARK: - Reminder Offsets

    private func reminderOffsets(
        for event: WatchScheduleItem
    ) -> [Int] {

        var offsets:
            [Int] = []

        if event.remind10Minutes {
            offsets.append(10)
        }

        if event.remind5Minutes {
            offsets.append(5)
        }

        if event.remind1Minute {
            offsets.append(1)
        }

        return offsets
    }

    // MARK: - One Notification

    @discardableResult
    private func scheduleNotification(
        event: WatchScheduleItem,
        minutesBefore: Int
    ) async -> Bool {

        guard let notificationDate =
            Calendar.current.date(
                byAdding:
                    .minute,
                value:
                    -minutesBefore,
                to:
                    event.start
            )
        else {
            return false
        }

        guard notificationDate >
            Date()
        else {
            return false
        }

        let content =
            UNMutableNotificationContent()

        // MARK: Title

        content.title =
            notificationTitle(
                minutesBefore:
                    minutesBefore
            )

        // MARK: Body

        content.body =
            notificationBody(
                event
            )

        // MARK: Sound

        content.sound =
            .default

        // MARK: Time Sensitive

        content.interruptionLevel =
            .timeSensitive

        // MARK: Action Button

        content.categoryIdentifier =
            categoryIdentifier

        // MARK: Metadata

        content.userInfo = [
            "eventID":
                event.id.uuidString,
            "minutesBefore":
                minutesBefore
        ]

        // MARK: Trigger

        let components =
            Calendar.current
                .dateComponents(
                    [
                        .year,
                        .month,
                        .day,
                        .hour,
                        .minute
                    ],
                    from:
                        notificationDate
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
                        event:
                            event,
                        minutesBefore:
                            minutesBefore
                    ),
                content:
                    content,
                trigger:
                    trigger
            )

        do {
            try await
                UNUserNotificationCenter
                    .current()
                    .add(
                        request
                    )

            print(
                "Watch notification created: \(request.identifier)"
            )

            return true

        } catch {
            print(
                "Ошибка создания Watch notification: \(error)"
            )

            return false
        }
    }

    // MARK: - Identifier

    private func identifier(
        event: WatchScheduleItem,
        minutesBefore: Int
    ) -> String {

        return
            "raceassistant-watch-\(event.id.uuidString)-\(minutesBefore)"
    }

    // MARK: - Notification Title

    private func notificationTitle(
        minutesBefore: Int
    ) -> String {

        switch minutesBefore {

        case 1:
            return
                "ЧЕРЕЗ 1 МИНУТУ"

        case 5:
            return
                "ЧЕРЕЗ 5 МИНУТ"

        case 10:
            return
                "ЧЕРЕЗ 10 МИНУТ"

        default:
            return
                "ПРЕДСТОЯЩЕЕ СОБЫТИЕ"
        }
    }

    // MARK: - Notification Body

    private func notificationBody(
        _ event: WatchScheduleItem
    ) -> String {

        var parts:
            [String] = []

        // Главное — название активности.

        parts.append(
            event.title
        )

        // Затем классы.

        if !event.classes.isEmpty {

            parts.append(
                event.classes
                    .joined(
                        separator:
                            " · "
                    )
            )
        }

        // Роли намеренно не добавляем.
        //
        // Watch уже получил событие
        // согласно выбранной политике
        // уведомлений, а лишний текст
        // уменьшает заметность названия.

        return parts.joined(
            separator:
                " · "
        )
    }

    // MARK: - Foreground Notification

    func userNotificationCenter(
        _ center:
            UNUserNotificationCenter,
        willPresent notification:
            UNNotification,
        withCompletionHandler
            completionHandler:
            @escaping (
                UNNotificationPresentationOptions
            ) -> Void
    ) {

        // Показываем уведомление даже если
        // Race Assistant сейчас открыт
        // непосредственно на часах.

        completionHandler([
            .banner,
            .list,
            .sound
        ])
    }

    // MARK: - Notification Response

    func userNotificationCenter(
        _ center:
            UNUserNotificationCenter,
        didReceive response:
            UNNotificationResponse,
        withCompletionHandler
            completionHandler:
            @escaping () -> Void
    ) {

        switch response.actionIdentifier {

        case acknowledgeActionIdentifier:

            let identifier =
                response.notification
                    .request
                    .identifier

            // После "ПРИНЯТО"
            // убираем уведомление
            // из Notification Center.

            center
                .removeDeliveredNotifications(
                    withIdentifiers: [
                        identifier
                    ]
                )

            print(
                "Watch notification acknowledged: \(identifier)"
            )

        case
            UNNotificationDefaultActionIdentifier:

            print(
                "Watch notification opened"
            )

        default:
            break
        }

        completionHandler()
    }
}
