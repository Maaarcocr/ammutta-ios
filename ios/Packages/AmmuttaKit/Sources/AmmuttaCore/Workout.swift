import Foundation

public enum SetStatus: Hashable, Codable, Sendable {
    case pending
    case logged(at: Date)
    case skipped(at: Date)

    public var isPending: Bool { if case .pending = self { true } else { false } }
    public var isLogged: Bool { if case .logged = self { true } else { false } }
    public var isSkipped: Bool { if case .skipped = self { true } else { false } }

    public var loggedAt: Date? {
        if case .logged(let date) = self { return date }
        return nil
    }
}

/// One set in a workout. `target` is what the plan said; `value` is what will be
/// (or was) logged, and stays editable until the workout finishes.
public struct WorkoutSet: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var target: SetValue
    public var value: SetValue
    public var status: SetStatus

    public init(id: UUID = UUID(), target: SetValue, value: SetValue? = nil, status: SetStatus = .pending) {
        self.id = id
        self.target = target
        self.value = value ?? target
        self.status = status
    }
}

public struct WorkoutExercise: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var exercise: ExerciseRef
    public var kind: TrackingKind
    /// Custom exercise name at start time; a fallback if the exercise is later deleted.
    public var nameSnapshot: String?
    public var restSeconds: Int
    public var sets: [WorkoutSet]

    public init(id: UUID = UUID(), exercise: ExerciseRef, kind: TrackingKind, nameSnapshot: String? = nil, restSeconds: Int, sets: [WorkoutSet]) {
        self.id = id
        self.exercise = exercise
        self.kind = kind
        self.nameSnapshot = nameSnapshot
        self.restSeconds = restSeconds
        self.sets = sets
    }

    public var loggedCount: Int { sets.count(where: { $0.status.isLogged }) }
}

/// A running countdown, stored as absolute times so it survives backgrounding and relaunch.
public enum ActiveTimer: Hashable, Codable, Sendable {
    case rest(afterSet: UUID, startedAt: Date, endsAt: Date)
    case work(set: UUID, startedAt: Date, endsAt: Date)

    public var startedAt: Date {
        switch self {
        case .rest(_, let startedAt, _), .work(_, let startedAt, _): startedAt
        }
    }

    public var endsAt: Date {
        switch self {
        case .rest(_, _, let endsAt), .work(_, _, let endsAt): endsAt
        }
    }

    public var isRest: Bool { if case .rest = self { true } else { false } }

    public var workSetID: UUID? {
        if case .work(let id, _, _) = self { return id }
        return nil
    }
}

/// One performance of a plan. Plan data is copied in at start, so later plan edits never change it.
public struct Workout: Hashable, Codable, Sendable, Identifiable {
    public var id: WorkoutID
    public var planID: PlanID?
    public var planName: String
    public var startedAt: Date
    public var endedAt: Date?
    public var exercises: [WorkoutExercise]
    public var timer: ActiveTimer?

    public init(id: WorkoutID = WorkoutID(), planID: PlanID?, planName: String, startedAt: Date, endedAt: Date? = nil, exercises: [WorkoutExercise], timer: ActiveTimer? = nil) {
        self.id = id
        self.planID = planID
        self.planName = planName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.timer = timer
    }

    public static func start(from plan: Plan, now: Date, customNames: [ExerciseID: String] = [:], id: WorkoutID = WorkoutID()) -> Workout {
        let exercises = plan.exercises.map { planned in
            var snapshot: String?
            if case .custom(let exerciseID) = planned.exercise { snapshot = customNames[exerciseID] }
            return WorkoutExercise(
                exercise: planned.exercise,
                kind: planned.kind,
                nameSnapshot: snapshot,
                restSeconds: planned.restSeconds,
                sets: planned.sets.map { WorkoutSet(target: $0) }
            )
        }
        return Workout(id: id, planID: plan.id, planName: plan.name, startedAt: now, exercises: exercises)
    }

    public var isFinished: Bool { endedAt != nil }

    /// The first set still to do, in plan order.
    public var nextPendingSetID: UUID? {
        for exercise in exercises {
            if let set = exercise.sets.first(where: { $0.status.isPending }) { return set.id }
        }
        return nil
    }

    public var hasPendingSets: Bool { nextPendingSetID != nil }

    public func location(ofSet id: UUID) -> (exercise: Int, set: Int)? {
        for (exerciseIndex, exercise) in exercises.enumerated() {
            if let setIndex = exercise.sets.firstIndex(where: { $0.id == id }) {
                return (exerciseIndex, setIndex)
            }
        }
        return nil
    }

    public func set(_ id: UUID) -> WorkoutSet? {
        guard let location = location(ofSet: id) else { return nil }
        return exercises[location.exercise].sets[location.set]
    }
}
