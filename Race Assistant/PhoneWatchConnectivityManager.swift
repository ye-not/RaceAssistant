import Foundation
import SwiftData
import Combine
import WatchConnectivity
import UserNotifications

final class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneWatchConnectivityManager()

    @Published private(set)
    var activationState: WCSessionActivationState = .notActivated

    @Published private(set)
    var isPaired = false

    @Published private(set)
    var isWatchAppInstalled = false

    @Published private(set)
    var isReachable = false

    @Published private(set)
    var watchNotificationsActive = false

    @Published private(set)
    var isWaitingForWatchSync = false

    private var pendingSyncToken: String?

    private var pendingNotificationIDs: [UUID] = []

    private override init() {
        super.init()

        guard WCSession.isSupported() else {
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()

        refreshStatus()
    }

    // MARK: - Status

    func refreshStatus() {
        guard WCSession.isSupported() else {
            return
        }

        let session =
            WCSession.default

        DispatchQueue.main.async {
            self.activationState =
                session.activationState

            self.isPaired =
                session.isPaired

            self.isWatchAppInstalled =
                session.isWatchAppInstalled

            self.isReachable =
                session.isReachable

            if !session.isPaired ||
                !session.isWatchAppInstalled {

                self.watchNotificationsActive =
                    false

                self.isWaitingForWatchSync =
                    false

                self.pendingSyncToken =
                    nil

                self.pendingNotificationIDs =
                    []
            }
        }
    }

    // MARK: - Can Use Watch

    var canUseWatch: Bool {
        guard WCSession.isSupported() else {
            return false
        }

        let session =
            WCSession.default

        return
            session.activationState == .activated &&
            session.isPaired &&
            session.isWatchAppInstalled
    }

    // MARK: - Send Raw Schedule

    func send(
        schedule: WatchScheduleData
    ) {
        guard WCSession.isSupported() else {
            print(
                "WatchConnectivity не поддерживается"
            )

            watchNotificationsActive =
                false

            return
        }

        let session =
            WCSession.default

        guard
            session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            print(
                "Watch недоступен для синхронизации"
            )

            watchNotificationsActive =
                false

            isWaitingForWatchSync =
                false

            pendingSyncToken =
                nil

            pendingNotificationIDs =
                []

            return
        }

        do {
            let data =
                try JSONEncoder()
                    .encode(
                        schedule
                    )

            let syncToken =
                UUID().uuidString

            pendingSyncToken =
                syncToken

            pendingNotificationIDs =
                schedule.events.map {
                    $0.id
                }

            isWaitingForWatchSync =
                true

            watchNotificationsActive =
                false

            let payload: [String: Any] = [
                "schedule": data,
                "syncToken": syncToken,
                "sentAt": Date().timeIntervalSince1970
            ]
            try session.updateApplicationContext(payload)
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { error in
                    print("Instant schedule delivery: \(error)")
                }
            }

            print(
                "Расписание отправлено на Watch: \(schedule.events.count) событий"
            )

            print(
                "Ожидаем подтверждение Watch: \(syncToken)"
            )

        } catch {
            watchNotificationsActive =
                false

            isWaitingForWatchSync =
                false

            pendingSyncToken =
                nil

            pendingNotificationIDs =
                []

            print(
                "Ошибка отправки расписания на Watch: \(error)"
            )
        }
    }

    @MainActor
    func sendPreferredStage() {
        let stages = (try? AppModelContainer.shared.mainContext.fetch(FetchDescriptor<Stage>())) ?? []
        let now = Date()
        let nonempty = stages.filter { !$0.scheduleEvents.isEmpty }
        let upcoming = nonempty.filter { $0.endDate >= Calendar.current.startOfDay(for: now) }.sorted {
            if ($0.myRole != nil) != ($1.myRole != nil) { return $0.myRole != nil }
            return $0.startDate < $1.startDate
        }
        if let stage = SchedulePresentation.workingStage(nonempty, now: now)
            ?? SchedulePresentation.todayStages(nonempty, now: now).first ?? upcoming.first {
            send(stage: stage)
        } else if let data = WCSession.default.applicationContext["schedule"] as? Data,
                  let schedule = try? JSONDecoder().decode(WatchScheduleData.self, from: data) {
            send(schedule: schedule)
        }
    }

    // MARK: - Send Stage

    @MainActor
    func send(stage requestedStage: Stage) {
        let stages = (try? AppModelContainer.shared.mainContext.fetch(FetchDescriptor<Stage>())) ?? []
        let stage = SchedulePresentation.workingStage(stages.filter { !$0.scheduleEvents.isEmpty }, now: .now) ?? requestedStage

        // Передаём на Watch всё расписание этапа,
        // а не только сегодняшний день.
        //
        // Завершённые вручную события
        // исключаем.

        let events =
            stage.scheduleEvents
                .filter {
                    $0.status != "finished"
                }
                .sorted {
                    $0.plannedStart <
                    $1.plannedStart
                }

        let watchEvents =
            events.map { event in

                let shouldNotify =
                    shouldWatchNotify(
                        event: event,
                        stage: stage
                    )

                return WatchScheduleItem(
                    id:
                        event.notificationID,

                    title:
                        event.title,

                    start:
                        event.plannedStart,

                    duration:
                        event.plannedDuration,

                    classes:
                        event.eventClasses
                            .compactMap {
                                $0.raceClass
                            }
                            .map {
                                $0.shortName.isEmpty
                                    ? $0.name
                                    : $0.shortName
                            }
                            .sorted(),

                    roles:
                        event.eventRoles
                            .compactMap {
                                $0.role
                            }
                            .map {
                                $0.shortName.isEmpty
                                    ? $0.name
                                    : $0.shortName
                            }
                            .sorted(),

                    isRace:
                        event.isRace,

                    groupTitle: SchedulePresentation.groupTitle(event),

                    // Флаги теперь формируются
                    // из настроек всего этапа.

                    remind10Minutes:
                        shouldNotify
                        &&
                        stage.stageRemind10Minutes,

                    remind5Minutes:
                        shouldNotify
                        &&
                        stage.stageRemind5Minutes,

                    remind1Minute:
                        shouldNotify
                        &&
                        stage.stageRemind1Minute
                )
            }

        let championshipName =
            stage.season?
                .championship?
                .name
            ?? ""

        let seasonYear =
            stage.season?.year
            ?? 0

        let circuitName =
            stage.circuit?
                .name
            ?? ""

        let myRoleName: String

        if let role =
            stage.myRole {

            myRoleName =
                role.shortName.isEmpty
                ? role.name
                : role.shortName

        } else {
            myRoleName = ""
        }

        let schedule =
            WatchScheduleData(
                championshipName:
                    championshipName,

                seasonYear:
                    seasonYear,

                stageName:
                    stage.name,

                circuitName:
                    circuitName,

                myRole:
                    myRoleName,

                events:
                    watchEvents
            )

        send(
            schedule: schedule
        )
    }

    // MARK: - Watch Notification Filtering

    private func shouldWatchNotify(
        event: ScheduleEvent,
        stage: Stage
    ) -> Bool {

        switch stage.notificationMode {

        case .none:
            return false

        case .all:
            return true

        case .myRole:

            guard let myRole =
                stage.myRole
            else {
                return false
            }

            // Если роли у события не заполнены,
            // в режиме "По моей роли"
            // уведомление не создаём.

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

                    return
                        role === myRole
                }
        }
    }

    // MARK: - Watch Acknowledgement

    private func handleAcknowledgement(
        token: String
    ) {
        guard
            token == pendingSyncToken
        else {
            print(
                "Получено подтверждение устаревшей синхронизации: \(token)"
            )

            return
        }

        let idsToRemove =
            pendingNotificationIDs

        DispatchQueue.main.async {
            self.watchNotificationsActive =
                true

            self.isWaitingForWatchSync =
                false

            self.pendingSyncToken =
                nil

            self.pendingNotificationIDs =
                []
        }

        removePhoneNotifications(
            eventIDs:
                idsToRemove
        )

        print(
            "Watch подтвердил получение расписания"
        )

        print(
            "iPhone fallback-уведомления удалены: \(idsToRemove.count) событий"
        )
    }

    // MARK: - Remove Phone Fallback

    private func removePhoneNotifications(
        eventIDs: [UUID]
    ) {
        let identifiers =
            eventIDs.flatMap { id in

                [10, 5, 1].map {
                    minutes in

                    "raceassistant-\(id.uuidString)-\(minutes)"
                }
            }

        UNUserNotificationCenter
            .current()
            .removePendingNotificationRequests(
                withIdentifiers:
                    identifiers
            )
    }
}


// MARK: - WCSessionDelegate

extension PhoneWatchConnectivityManager:
    WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState:
            WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.activationState =
                activationState

            self.isPaired =
                session.isPaired

            self.isWatchAppInstalled =
                session.isWatchAppInstalled

            self.isReachable =
                session.isReachable

            if !session.isPaired ||
                !session.isWatchAppInstalled {

                self.watchNotificationsActive =
                    false
            }
        }

        if activationState == .activated {
            Task { @MainActor in self.sendPreferredStage() }
        }
        if let error {
            print(
                "iPhone WatchConnectivity activation error: \(error)"
            )
        } else {
            print(
                "iPhone WatchConnectivity activated: \(activationState.rawValue)"
            )
        }
    }

    // MARK: - Instant Acknowledgement

    func session(
        _ session: WCSession,
        didReceiveMessage message:
            [String: Any]
    ) {
        if message["requestSchedule"] as? Bool == true {
            Task { @MainActor in self.sendPreferredStage() }
            return
        }
        guard let token =
            message[
                "scheduleAcknowledged"
            ] as? String
        else {
            return
        }

        handleAcknowledgement(
            token: token
        )
    }

    // MARK: - Background Acknowledgement

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo:
            [String: Any]
    ) {
        guard let token =
            userInfo[
                "scheduleAcknowledged"
            ] as? String
        else {
            return
        }

        handleAcknowledgement(
            token: token
        )
    }

    func sessionReachabilityDidChange(
        _ session: WCSession
    ) {
        refreshStatus()
        if session.isReachable { Task { @MainActor in self.sendPreferredStage() } }
    }

    func sessionWatchStateDidChange(
        _ session: WCSession
    ) {
        refreshStatus()
        Task { @MainActor in self.sendPreferredStage() }
    }

    func sessionDidBecomeInactive(
        _ session: WCSession
    ) {
        refreshStatus()
    }

    func sessionDidDeactivate(
        _ session: WCSession
    ) {
        refreshStatus()

        session.activate()
    }
}
