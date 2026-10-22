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

/// Updates and endings run one after another in the order they were requested, so a quick
/// "log set, skip rest" can never leave a stale countdown on the Lock Screen.
///
/// `Activity` is not Sendable, so only its ID is kept here; the background steps look it up.
@MainActor
final class LiveActivityPresenter: WorkoutActivityPresenting {
    private var activityID: String?
    private var lastState: WorkoutActivityAttributes.ContentState?
    private var queue: Task<Void, Never>?

    func show(_ attributes: WorkoutActivityAttributes, _ state: WorkoutActivityAttributes.ContentState) {
        // After a relaunch, reattach to the activity the previous process started.
        if activityID == nil {
            activityID = Activity<WorkoutActivityAttributes>.activities.first { $0.attributes == attributes }?.id
        }
        guard state != lastState else { return }
        lastState = state
        if let id = activityID {
            enqueue { await Self.update(id: id, state: state) }
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
        // End exactly the activities that exist now, so a workout started right after is untouched.
        let ids = Activity<WorkoutActivityAttributes>.activities.map(\.id)
        activityID = nil
        lastState = nil
        enqueue { await Self.end(ids: ids) }
    }

    private func enqueue(_ step: @escaping @Sendable () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await step()
        }
    }

    @concurrent
    private nonisolated static func update(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    @concurrent
    private nonisolated static func end(ids: [String]) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where ids.contains(activity.id) {
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
