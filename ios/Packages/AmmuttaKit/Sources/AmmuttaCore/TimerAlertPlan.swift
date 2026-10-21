import Foundation

/// The one system alert an active workout should have pending right now, derived purely from
/// its state. The app schedules exactly this alert (replacing any previous one), so a stale
/// alert can never fire after a timer is skipped, adjusted or finished.
public struct TimerAlertPlan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Rest ends; `nextSet` is the set to do next, if any.
        case restOver(nextSet: UUID?)
        /// A timed set's countdown reaches zero.
        case workDone(set: UUID)
    }

    public var fireDate: Date
    public var kind: Kind

    public init(fireDate: Date, kind: Kind) {
        self.fireDate = fireDate
        self.kind = kind
    }
}

extension Workout {
    /// nil when the workout is finished, has no timer, or its deadline has already passed.
    public func pendingTimerAlert(now: Date) -> TimerAlertPlan? {
        guard endedAt == nil, let timer, timer.endsAt > now else { return nil }
        switch timer {
        case .rest:
            return TimerAlertPlan(fireDate: timer.endsAt, kind: .restOver(nextSet: nextPendingSetID))
        case .work(let set, _, _):
            return TimerAlertPlan(fireDate: timer.endsAt, kind: .workDone(set: set))
        }
    }
}
