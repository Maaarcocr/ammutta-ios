import ActivityKit
import Foundation

/// Shows the active workout as a Live Activity (Lock Screen and Dynamic Island).
@MainActor
protocol WorkoutActivityPresenting: AnyObject, Sendable {
    /// Starts the Live Activity, or updates it when the state changed.
    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState)
    /// Ends it, for example when the workout finishes or is discarded.
    func end()
}

@MainActor
final class LiveActivityPresenter: WorkoutActivityPresenting {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?

    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState) {
        // After a relaunch, reattach to the activity the previous process started.
        if activity == nil {
            activity = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes == attributes }
        }
        guard state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            lastState = nil
        }
    }

    func end() {
        activity = nil
        lastState = nil
        // End every Ammutta activity, including any left over from an earlier launch.
        let running = Activity<WorkoutActivityAttributes>.activities
        Task {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// No Live Activity: unit tests, UI tests and previews.
@MainActor
final class DisabledActivityPresenter: WorkoutActivityPresenting {
    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState) {}
    func end() {}
}
