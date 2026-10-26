import AlarmKit
import Foundation

/// What a rest or set alarm carries, so the system's own Live Activity for it (drawn by the
/// widget extension) can show the same countdown as the workout's. Text arrives localized.
nonisolated struct TimerAlarmMetadata: AlarmMetadata {
    /// "Rest" or "Set in progress".
    var label: String
    var startsAt: Date
    var endsAt: Date
}
