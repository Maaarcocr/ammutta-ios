import AmmuttaCore
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "dev.ammutta.app", category: "WorkoutSession")

/// Owns the active workout. Each user action is reduced by the pure WorkoutEngine, saved
/// immediately, the in-app timer is rescheduled, and the system alert is synced so the phone
/// alerts on time even when locked.
@Observable
final class WorkoutSession: Identifiable {
    let id: WorkoutID
    private(set) var workout: Workout
    /// Increments when a countdown runs out while the app is open; drives the haptic.
    private(set) var timerEndedCount = 0
    /// True when the user declined notifications: timers then only alert inside the app.
    private(set) var alertsOff = false

    @ObservationIgnored private let persist: (Workout) -> Void
    @ObservationIgnored private let alerts: any TimerAlerting
    @ObservationIgnored private let alertContent: (TimerAlertPlan, Workout) -> TimerAlertRequest
    @ObservationIgnored private let activity: any WorkoutActivityPresenting
    @ObservationIgnored private let activityContent: (Workout) -> (WorkoutActivityAttributes, WorkoutActivityAttributes.ContentState)
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var alertQueue: Task<Void, Never>?
    @ObservationIgnored private var scheduledAlert: TimerAlertRequest?
    @ObservationIgnored private var hasSyncedAlert = false

    init(
        workout: Workout,
        alerts: any TimerAlerting,
        alertContent: @escaping (TimerAlertPlan, Workout) -> TimerAlertRequest,
        activity: any WorkoutActivityPresenting,
        activityContent: @escaping (Workout) -> (WorkoutActivityAttributes, WorkoutActivityAttributes.ContentState),
        persist: @escaping (Workout) -> Void
    ) {
        id = workout.id
        self.workout = workout
        self.alerts = alerts
        self.alertContent = alertContent
        self.activity = activity
        self.activityContent = activityContent
        self.persist = persist
        refresh()
    }

    var isFinished: Bool { workout.endedAt != nil }

    func send(_ event: WorkoutEvent) {
        do {
            let updated = try WorkoutEngine.reduce(workout, event, now: .now)
            if updated != workout {
                workout = updated
                persist(updated)
            }
        } catch {
            // Stale taps (for example on a set that was just removed) are ignored.
            logger.debug("Ignored workout event: \(String(describing: error), privacy: .public)")
        }
        scheduleTimer()
        syncAlert()
        syncActivity()
    }

    /// Stores a heart-rate reading. Saved every 30 seconds of readings; the rest are saved
    /// with the next set or when the workout ends.
    func recordHeartRate(_ bpm: Int, at date: Date) {
        guard workout.recordHeartRate(bpm, at: date) else { return }
        if workout.heartRate.count.isMultiple(of: 6) {
            persist(workout)
        }
    }

    /// Settles a deadline that passed while the app was in the background or not running.
    func refresh() {
        guard !isFinished else {
            syncAlert()
            syncActivity()
            return
        }
        if let timer = workout.timer, timer.endsAt <= .now {
            send(.timerElapsed)
        } else {
            scheduleTimer()
            syncAlert()
            syncActivity()
        }
    }

    /// Removes the pending system alert and the Live Activity, for example when the workout is discarded.
    func close() {
        enqueueAlert(nil)
        activity.end()
    }

    private func syncActivity() {
        if isFinished {
            activity.end()
        } else {
            let (attributes, state) = activityContent(workout)
            activity.show(attributes, state)
        }
    }

    /// Lets tests wait until queued alert changes have reached the alert service.
    func alertsSettled() async {
        await alertQueue?.value
    }

    private var alertID: String { "ammutta.timer.\(workout.id.rawValue.uuidString)" }

    private func syncAlert() {
        let desired = workout.pendingTimerAlert(now: .now).map { alertContent($0, workout) }
        guard !hasSyncedAlert || desired != scheduledAlert else { return }
        enqueueAlert(desired)
    }

    /// Alert changes run in order, so a quick skip after a log can never leave a stale alert.
    private func enqueueAlert(_ alert: TimerAlertRequest?) {
        hasSyncedAlert = true
        scheduledAlert = alert
        let id = alertID
        let previous = alertQueue
        let service = alerts
        alertQueue = Task { [weak self] in
            await previous?.value
            if alert != nil {
                var status = await service.authorization()
                if status == .notDetermined {
                    status = await service.requestAuthorization()
                }
                self?.alertsOff = status == .denied
            }
            await service.replace(id: id, with: alert)
        }
    }

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = nil
        guard !isFinished, let endsAt = workout.timer?.endsAt else { return }
        timerTask = Task { [weak self] in
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.timerFired()
        }
    }

    private func timerFired() {
        timerEndedCount += 1
        send(.timerElapsed)
    }
}
