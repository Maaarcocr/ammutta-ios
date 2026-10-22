import Foundation

/// What AI agents see through the Ammutta connector: plans, workout history and exercises,
/// in plain readable fields. Weights use the user's unit; plan sets use the plan-link syntax
/// (`3x8@60`, `45s`), the same syntax agents use to write plans.
public struct AgentSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    /// "kg" or "lb".
    public var unit: String
    public var plans: [Plan]
    /// Finished workouts, newest first.
    public var workouts: [Workout]
    public var customExercises: [CustomExercise]
    public var builtInExercises: [BuiltInExercise]

    public struct Plan: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var exercises: [PlanExercise]
    }

    public struct PlanExercise: Codable, Equatable, Sendable {
        /// A built-in key or a custom exercise name, as accepted by `create_plan`.
        public var exercise: String
        public var name: String
        public var sets: String
        public var restSeconds: Int
    }

    public struct Workout: Codable, Equatable, Sendable {
        public var id: String
        public var plan: String
        public var startedAt: Date
        public var endedAt: Date
        public var durationMinutes: Int
        public var averageHeartRate: Int?
        public var maxHeartRate: Int?
        public var exercises: [WorkoutExercise]
    }

    public struct WorkoutExercise: Codable, Equatable, Sendable {
        public var exercise: String
        public var name: String
        public var sets: [WorkoutSet]
    }

    public struct WorkoutSet: Codable, Equatable, Sendable {
        /// "done", "skipped" or "not done".
        public var status: String
        public var reps: Int?
        public var weight: Double?
        public var seconds: Int?
    }

    public struct CustomExercise: Codable, Equatable, Sendable {
        public var name: String
        /// "reps" or "timed".
        public var kind: String
    }

    public struct BuiltInExercise: Codable, Equatable, Sendable {
        public var key: String
        public var name: String
        public var kind: String
        public var equipment: String
        public var muscle: String
    }
}

extension AgentSnapshot {
    /// - Parameter builtInName: the English name of a built-in exercise key.
    public init(
        plans: [AmmuttaCore.Plan],
        workouts: [AmmuttaCore.Workout],
        customExercises: [AmmuttaCore.CustomExercise],
        unit: WeightUnit,
        now: Date,
        builtInName: (String) -> String
    ) {
        let customNames = Dictionary(customExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        func reference(_ ref: ExerciseRef, snapshot: String? = nil) -> (exercise: String, name: String) {
            switch ref {
            case .builtIn(let key):
                return (key, builtInName(key))
            case .custom(let id):
                let name = customNames[id] ?? snapshot ?? "Deleted exercise"
                return (name, name)
            }
        }

        generatedAt = now
        self.unit = unit == .pounds ? "lb" : "kg"
        self.plans = plans.map { plan in
            Plan(id: plan.id.rawValue.uuidString, name: plan.name, exercises: plan.exercises.map { exercise in
                let (key, name) = reference(exercise.exercise)
                return PlanExercise(
                    exercise: key, name: name,
                    sets: PlanLink.encodeSets(exercise.sets, unit: unit), restSeconds: exercise.restSeconds
                )
            })
        }
        self.workouts = workouts
            .compactMap { workout -> Workout? in
                guard let end = workout.endedAt else { return nil }
                let summary = WorkoutSummary(workout)
                return Workout(
                    id: workout.id.rawValue.uuidString,
                    plan: workout.planName,
                    startedAt: workout.startedAt,
                    endedAt: end,
                    durationMinutes: Int((Double(summary.durationSeconds) / 60).rounded()),
                    averageHeartRate: summary.averageHeartRate,
                    maxHeartRate: summary.maxHeartRate,
                    exercises: workout.exercises.map { exercise in
                        let (key, name) = reference(exercise.exercise, snapshot: exercise.nameSnapshot)
                        return WorkoutExercise(exercise: key, name: name, sets: exercise.sets.map { set in
                            let status = switch set.status {
                            case .logged: "done"
                            case .skipped: "skipped"
                            case .pending: "not done"
                            }
                            return WorkoutSet(
                                status: status,
                                reps: set.value.reps,
                                weight: set.value.weight.map { $0.value(in: unit) },
                                seconds: set.value.seconds
                            )
                        })
                    }
                )
            }
            .sorted { $0.startedAt > $1.startedAt }
        self.customExercises = customExercises
            .map { CustomExercise(name: $0.name, kind: $0.kind == .reps ? "reps" : "timed") }
            .sorted { $0.name < $1.name }
        builtInExercises = ExerciseCatalog.all.map { exercise in
            BuiltInExercise(
                key: exercise.key, name: builtInName(exercise.key),
                kind: exercise.kind == .reps ? "reps" : "timed",
                equipment: exercise.equipment.rawValue, muscle: exercise.muscle.rawValue
            )
        }
    }
}
