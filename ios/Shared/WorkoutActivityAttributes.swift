import ActivityKit
import Foundation

/// Shared by the app (which starts and updates the Live Activity) and the widget extension
/// (which draws it). All text arrives already localized from the app; countdowns are drawn
/// by the system from absolute dates, so they stay exact while the app is suspended.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes, Hashable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The exercise to do now or next, or the plan name when every set is done.
        var exercise: String
        /// For example "Set 2 of 3".
        var detail: String
        /// "Rest" or "Set in progress" while a countdown runs.
        var timerLabel: String?
        var timerStart: Date?
        var timerEnd: Date?

        var hasCountdown: Bool {
            guard let timerStart, let timerEnd else { return false }
            return timerEnd > timerStart
        }
    }

    var planName: String
    var startedAt: Date
}
