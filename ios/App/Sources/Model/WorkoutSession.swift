import AmmuttaCore
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "dev.ammutta.app", category: "WorkoutSession")

/// Owns the active workout. Each user action is reduced by the pure WorkoutEngine,
/// saved immediately, and the next timer deadline is rescheduled.
@Observable
final class WorkoutSession: Identifiable {
    let id: WorkoutID
    private(set) var workout: Workout
    /// Increments when a countdown runs out while the app is open; drives the haptic.
    private(set) var timerEndedCount = 0

    @ObservationIgnored private let persist: (Workout) -> Void
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(workout: Workout, persist: @escaping (Workout) -> Void) {
        id = workout.id
        self.workout = workout
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
    }

    /// Settles a deadline that passed while the app was in the background or not running.
    func refresh() {
        guard !isFinished else { return }
        if let timer = workout.timer, timer.endsAt <= .now {
            send(.timerElapsed)
        } else {
            scheduleTimer()
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
