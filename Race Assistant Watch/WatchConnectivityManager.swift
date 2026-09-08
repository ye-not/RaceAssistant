import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published private(set)
    var scheduleData: WatchScheduleData?

    @Published private(set)
    var activationState: WCSessionActivationState = .notActivated

    @Published private(set)
    var isReachable = false

    private override init() {
        super.init()

        guard WCSession.isSupported() else {
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refreshStatus() {
        let session = WCSession.default

        activationState = session.activationState
        isReachable = session.isReachable
    }

    // MARK: - Handle received schedule

    private func handle(
        schedule: WatchScheduleData,
        syncToken: String?
    ) {
        scheduleData = schedule

        Task {
            await WatchNotificationManager.shared
                .requestPermission()

            await WatchNotificationManager.shared
                .reschedule(
                    schedule: schedule
                )

            if let syncToken {
                sendAcknowledgement(
                    token: syncToken
                )
            }
        }
    }

    // MARK: - Acknowledgement

    private func sendAcknowledgement(
        token: String
    ) {
        let session = WCSession.default

        let payload: [String: Any] = [
            "scheduleAcknowledged": token
        ]

        if session.isReachable {
            session.sendMessage(
                payload,
                replyHandler: nil
            ) { error in
                print(
                    "Ошибка instant acknowledgement: \(error)"
                )

                session.transferUserInfo(
                    payload
                )
            }

            print(
                "Watch отправил instant acknowledgement"
            )

        } else {
            session.transferUserInfo(
                payload
            )

            print(
                "Watch поставил acknowledgement в очередь"
            )
        }
    }
}


// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print(
                "WatchConnectivity activation error: \(error)"
            )
        } else {
            print(
                "WatchConnectivity activated: \(activationState.rawValue)"
            )
        }

        Task { @MainActor in
            self.activationState = activationState
            self.isReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(
        _ session: WCSession
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // MARK: - Application Context

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data =
            applicationContext["schedule"] as? Data
        else {
            return
        }

        let syncToken =
            applicationContext["syncToken"] as? String

        do {
            let schedule =
                try JSONDecoder().decode(
                    WatchScheduleData.self,
                    from: data
                )

            Task { @MainActor in
                self.handle(
                    schedule: schedule,
                    syncToken: syncToken
                )
            }

        } catch {
            print(
                "Watch decode error: \(error)"
            )
        }
    }
}
