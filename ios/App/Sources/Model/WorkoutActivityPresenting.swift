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

/// Keeps only the activity's ID on the main actor. `Activity` is not Sendable, so updates and
/// endings look the activity up again inside a background function instead of passing it there.
@MainActor
final class LiveActivityPresenter: WorkoutActivityPresenting {
    private var activityID: String?
    private var lastState: WorkoutActivityAttributes.ContentState?

    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState) {
        // After a relaunch, reattach to the activity the previous process started.
        if activityID == nil {
            activityID = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes == attributes }?.id
        }
        guard state != lastState else { return }
        lastState = state
        if let activityID {
            Task { await Self.update(id: activityID, state: state) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let content = ActivityContent(state: state, staleDate: nil)
            activityID = try Activity.request(attributes: attributes, content: content, pushType: nil).id
        } catch {
            lastState = nil
        }
    }

    func end() {
        activityID = nil
        lastState = nil
        // End every Ammutta activity, including any left over from an earlier launch.
        Task { await Self.endAll() }
    }

    @concurrent
    private nonisolated static func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    @concurrent
    private nonisolated static func endAll() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

/// No Live Activity: unit tests, UI tests and previews.
@MainActor
final class DisabledActivityPresenter: WorkoutActivityPresenting {
    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState) {}
    func end() {}
}
