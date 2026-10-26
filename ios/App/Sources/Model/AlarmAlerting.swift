@preconcurrency import ActivityKit
@preconcurrency import AlarmKit
import Foundation
import SwiftUI

/// The short chime timer alerts play, bundled with the app (`Resources/rest-chime.wav`).
nonisolated enum TimerSound {
    static let fileName = "rest-chime.wav"
}

/// Timer alerts as AlarmKit alarms (product spec §6.4): they sound even in silent mode or a
/// Focus, like the Clock app. The workout's own Live Activity shows the countdown, so the alarm
/// only has an alert state, at a fixed time. Only Sendable values cross into AlarmKit.
@MainActor
final class AlarmKitAlerting: TimerAlerting {
    func authorization() async -> AlertAuthorization {
        Self.map(Self.state())
    }

    func requestAuthorization() async -> AlertAuthorization {
        await Self.request()
        return Self.map(Self.state())
    }

    func replace(id: String, with alert: TimerAlertRequest?) async {
        let metadata = alert.map {
            TimerAlarmMetadata(label: $0.countdownLabel ?? $0.title, startsAt: $0.countdownStart ?? .now, endsAt: $0.fireDate)
        }
        await Self.schedule(title: alert?.title, metadata: metadata, stopLabel: L10n.alarmStop)
    }

    func dismissFired(id: String) async {
        await Self.stopFired()
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlertAuthorization {
        switch state {
        case .authorized: .allowed
        case .denied: .denied
        default: .notDetermined
        }
    }

    private nonisolated static func state() -> AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    private nonisolated static func request() async {
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    /// An active workout has at most one pending alert, so every change first cancels the
    /// app's alarms that haven't gone off yet, including any left over from before a relaunch.
    /// One that is going off (or due within a moment) stays until `stopFired`.
    private nonisolated static func schedule(title: String?, metadata: TimerAlarmMetadata?, stopLabel: LocalizedStringResource) async {
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] where !hasFired(alarm) {
            try? manager.cancel(id: alarm.id)
        }
        guard let title, let metadata, metadata.endsAt > .now else { return }
        let date = metadata.endsAt
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        } else {
            // iOS 26.0 needs the stop button spelled out.
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: stopLabel, textColor: .white, systemImageName: "stop.circle"),
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
        }
        let attributes = AlarmAttributes<TimerAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: .accentColor
        )
        let configuration = AlarmManager.AlarmConfiguration<TimerAlarmMetadata>.alarm(
            schedule: .fixed(date),
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: .named(TimerSound.fileName)
        )
        _ = try? await manager.schedule(id: UUID(), configuration: configuration)
    }

    /// Going off, or due within two seconds: the app's own timer can end a moment before the
    /// system starts the alert, and that alarm must not be cancelled.
    private nonisolated static func hasFired(_ alarm: Alarm) -> Bool {
        if case .alerting = alarm.state { return true }
        if case .fixed(let date)? = alarm.schedule { return date <= .now.addingTimeInterval(2) }
        return false
    }

    private nonisolated static func stopFired() async {
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] where hasFired(alarm) {
            if case .alerting = alarm.state {
                try? manager.stop(id: alarm.id)
            } else {
                try? manager.cancel(id: alarm.id)
            }
        }
    }
}

/// The alert path the app uses: AlarmKit alarms, or local notifications when alarms are
/// declined. Exactly one of the two holds the pending alert.
@MainActor
final class SystemAlerting: TimerAlerting {
    private let alarms: any TimerAlerting
    private let notifications: any TimerAlerting

    init(alarms: any TimerAlerting, notifications: any TimerAlerting) {
        self.alarms = alarms
        self.notifications = notifications
    }

    func authorization() async -> AlertAuthorization {
        let alarmStatus = await alarms.authorization()
        return alarmStatus == .denied ? await notifications.authorization() : alarmStatus
    }

    func requestAuthorization() async -> AlertAuthorization {
        let alarmStatus = await alarms.requestAuthorization()
        return alarmStatus == .denied ? await notifications.requestAuthorization() : alarmStatus
    }

    func replace(id: String, with alert: TimerAlertRequest?) async {
        let useAlarms = await alarms.authorization() == .allowed
        await alarms.replace(id: id, with: useAlarms ? alert : nil)
        await notifications.replace(id: id, with: useAlarms ? nil : alert)
    }

    func dismissFired(id: String) async {
        await alarms.dismissFired(id: id)
        await notifications.dismissFired(id: id)
    }
}
