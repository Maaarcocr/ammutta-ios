import Foundation
import UserNotifications

enum AlertAuthorization: Equatable, Sendable {
    case notDetermined, allowed, denied
}

/// The chime timer alerts play, bundled with the app (`Resources/rest-chime.wav`).
nonisolated enum TimerSound {
    static let fileName = "rest-chime.wav"
}

/// One scheduled alert, already localized.
struct TimerAlertRequest: Equatable, Sendable {
    var fireDate: Date
    var title: String
    var body: String
}

/// Delivers timer alerts when the app is in the background, the phone is locked, or the app
/// isn't running (product spec §6.4). The workout's Live Activity shows the countdown.
@MainActor
protocol TimerAlerting: AnyObject, Sendable {
    func authorization() async -> AlertAuthorization
    func requestAuthorization() async -> AlertAuthorization
    /// Replaces whatever alert `id` had pending with `alert`, or removes it when `alert` is
    /// nil. An alert that already went off stays, so it isn't swept away the moment it fires.
    func replace(id: String, with alert: TimerAlertRequest?) async
    /// The person is using the app again: puts away an alert that already went off.
    func dismissFired(id: String) async
}

/// Timer alerts as local notifications with the app's chime. Only Sendable values cross into
/// the UserNotifications calls.
@MainActor
final class NotificationAlerting: TimerAlerting {
    private let foreground = ForegroundChime()

    init() {
        // The notification center holds its delegate weakly; this object keeps it.
        UNUserNotificationCenter.current().delegate = foreground
    }

    func authorization() async -> AlertAuthorization {
        Self.map(await Self.currentStatus())
    }

    func requestAuthorization() async -> AlertAuthorization {
        _ = await Self.request()
        return Self.map(await Self.currentStatus())
    }

    func replace(id: String, with alert: TimerAlertRequest?) async {
        await Self.schedule(id: id, alert: alert)
    }

    func dismissFired(id: String) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    private static func map(_ status: UNAuthorizationStatus) -> AlertAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    private nonisolated static func currentStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private nonisolated static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private nonisolated static func schedule(id: String, alert: TimerAlertRequest?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let alert else { return }
        let delay = alert.fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = UNNotificationSound(named: UNNotificationSoundName(TimerSound.fileName))
        content.interruptionLevel = .active
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// With the app open, a timer alert plays its chime without a banner: the workout screen
/// already shows that the timer ended.
nonisolated final class ForegroundChime: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.sound]
    }
}

/// No system alerts: unit tests, UI tests and previews.
@MainActor
final class DisabledAlerting: TimerAlerting {
    func authorization() async -> AlertAuthorization { .allowed }
    func requestAuthorization() async -> AlertAuthorization { .allowed }
    func replace(id: String, with alert: TimerAlertRequest?) async {}
    func dismissFired(id: String) async {}
}
