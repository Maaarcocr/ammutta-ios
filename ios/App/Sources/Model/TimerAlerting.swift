import Foundation
import UserNotifications

enum AlertAuthorization: Equatable, Sendable {
    case notDetermined, allowed, denied
}

/// One scheduled alert, already localized.
struct TimerAlertRequest: Equatable, Sendable {
    var fireDate: Date
    var title: String
    var body: String
}

/// Delivers timer alerts when the app is in the background, the phone is locked, or the app
/// isn't running. Product spec §6.4: AlarmKit alarms first (`AlarmKitAlerting`), local
/// notifications when alarms are declined (`SystemAlerting` picks).
@MainActor
protocol TimerAlerting: AnyObject, Sendable {
    func authorization() async -> AlertAuthorization
    func requestAuthorization() async -> AlertAuthorization
    /// Replaces whatever alert `id` had with `alert`, or removes it when `alert` is nil.
    func replace(id: String, with alert: TimerAlertRequest?) async
}

/// Local notifications, the fallback when AlarmKit is declined. Only Sendable values cross
/// into the UserNotifications calls.
@MainActor
final class NotificationAlerting: TimerAlerting {
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
        center.removeDeliveredNotifications(withIdentifiers: [id])
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

/// No system alerts: unit tests, UI tests and previews.
@MainActor
final class DisabledAlerting: TimerAlerting {
    func authorization() async -> AlertAuthorization { .allowed }
    func requestAuthorization() async -> AlertAuthorization { .allowed }
    func replace(id: String, with alert: TimerAlertRequest?) async {}
}
