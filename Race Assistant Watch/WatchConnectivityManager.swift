import Foundation
import Combine
import WatchConnectivity

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    @Published private(set) var scheduleData: WatchScheduleData?
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    @Published private(set) var isReachable = false

    private let cacheKey = "raceassistant.watch.schedule.v1"
    private let revisionKey = "raceassistant.watch.schedule.revision"
    private var newestRevision: Double = 0
    private var appliedData: Data?
    private var pending: (schedule: WatchScheduleData, data: Data, token: String?)?
    private var applyingNotifications = false
    private var lastRequest = Date.distantPast

    private override init() {
        super.init()
        newestRevision = UserDefaults.standard.double(forKey: revisionKey)
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            scheduleData = try? JSONDecoder().decode(WatchScheduleData.self, from: data)
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func refreshStatus() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        activationState = session.activationState
        isReachable = session.isReachable
        guard activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        if isReachable, Date().timeIntervalSince(lastRequest) > 5 {
            lastRequest = Date()
            session.sendMessage(["requestSchedule": true], replyHandler: nil) { error in
                print("Запрос расписания: \(error)")
            }
        }
    }

    private func receive(_ payload: [String: Any]) {
        guard let data = payload["schedule"] as? Data else { return }
        let revision = (payload["sentAt"] as? Double) ?? 0.0
        guard revision >= newestRevision else { return }
        do {
            let schedule = try JSONDecoder().decode(WatchScheduleData.self, from: data)
            let token = payload["syncToken"] as? String
            newestRevision = revision
            scheduleData = schedule
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(revision, forKey: revisionKey)
            if data == appliedData, !applyingNotifications {
                if let token { acknowledge(token) }
                return
            }
            // Serialize notification replacement; a newer payload replaces queued work.
            pending = (schedule, data, token)
            guard !applyingNotifications else { return }
            applyingNotifications = true
            Task {
                await WatchNotificationManager.shared.requestPermission()
                while let job = pending {
                    pending = nil
                    await WatchNotificationManager.shared.reschedule(schedule: job.schedule)
                    appliedData = job.data
                    if pending == nil, let token = job.token { acknowledge(token) }
                }
                applyingNotifications = false
            }
        } catch {
            // Keep the last valid cache if the new payload cannot be decoded.
            print("Watch decode error: \(error)")
        }
    }

    private func acknowledge(_ token: String) {
        let session = WCSession.default
        let payload = ["scheduleAcknowledged": token]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in session.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.refreshStatus() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshStatus() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.receive(message) }
    }
}
