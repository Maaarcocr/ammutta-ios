@preconcurrency import ActivityKit
@preconcurrency import AlarmKit
import Foundation
import SwiftUI

/// The short chime timer alerts play, bundled with the app (`Resources/rest-chime.wav`).
nonisolated enum TimerSound {
    static let fileName = "rest-chime.wav"
}

/// What AlarmKit stores with each alarm. Ammutta needs nothing beyond the title.
nonisolated struct TimerAlarmMetadata: AlarmMetadata {}

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
        await Self.schedule(title: alert?.title, at: alert?.fireDate)
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
    /// app's alarms, including any left over from before a relaunch.
    private nonisolated static func schedule(title: String?, at date: Date?) async {
        let manager = AlarmManager.shared
        for alarm in (try? manager.alarms) ?? [] {
            try? manager.cancel(id: alarm.id)
        }
        guard let title, let date, date > .now else { return }
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes<TimerAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: TimerAlarmMetadata(),
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
}
