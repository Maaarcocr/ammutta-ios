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

    /// An exercise added during a workout. It repeats last time's sets when there are any (so the
    /// weights are already filled in), otherwise it starts with three default sets.
    public static func added(exercise: ExerciseRef, kind: TrackingKind, nameSnapshot: String?, restSeconds: Int, previous: [SetValue]) -> WorkoutExercise {
        let reusable = previous.filter { $0.kind == kind && $0.isValidTarget }.prefix(Limits.setsPerExercise.upperBound)
        let targets = reusable.isEmpty ? Array(repeating: SetValue.defaultValue(for: kind), count: 3) : Array(reusable)
        return WorkoutExercise(
            exercise: exercise,
            kind: kind,
            nameSnapshot: nameSnapshot,
            restSeconds: min(max(restSeconds, Limits.restSeconds.lowerBound), Limits.restSeconds.upperBound),
            sets: targets.map { WorkoutSet(target: $0) }
        )
    }
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
    /// Readings from a Bluetooth heart-rate sensor, oldest first, at most one every few seconds.
    public var heartRate: [HeartRateSample]

    public init(id: WorkoutID = WorkoutID(), planID: PlanID?, planName: String, startedAt: Date, endedAt: Date? = nil, exercises: [WorkoutExercise], timer: ActiveTimer? = nil, heartRate: [HeartRateSample] = []) {
        self.id = id
        self.planID = planID
        self.planName = planName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
        self.timer = timer
        self.heartRate = heartRate
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

    /// The workout as plan exercises, for saving it as a plan: what was logged, or the target for
    /// sets that weren't (or whose logged value isn't a valid target, such as 0 reps).
    public var planExercises: [PlanExercise] {
        exercises.map { exercise in
            PlanExercise(
                exercise: exercise.exercise,
                kind: exercise.kind,
                restSeconds: exercise.restSeconds,
                sets: exercise.sets.map { set in
                    set.status.isLogged && set.value.isValidTarget ? set.value : set.target
                }
            )
        }
    }

    /// True when the workout's exercises, or their order, differ from the plan's.
    public func changesExercises(of plan: Plan) -> Bool {
        exercises.map(\.exercise) != plan.exercises.map(\.exercise)
    }

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

extension Workout {
    private enum CodingKeys: String, CodingKey {
        case id, planID, planName, startedAt, endedAt, exercises, timer, heartRate
    }

    /// Workouts saved before heart rate existed have no `heartRate` key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(WorkoutID.self, forKey: .id),
            planID: try container.decodeIfPresent(PlanID.self, forKey: .planID),
            planName: try container.decode(String.self, forKey: .planName),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            exercises: try container.decode([WorkoutExercise].self, forKey: .exercises),
            timer: try container.decodeIfPresent(ActiveTimer.self, forKey: .timer),
            heartRate: try container.decodeIfPresent([HeartRateSample].self, forKey: .heartRate) ?? []
        )
    }
}
