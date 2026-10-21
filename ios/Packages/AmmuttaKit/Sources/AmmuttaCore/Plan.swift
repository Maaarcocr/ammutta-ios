import Foundation

/// An exercise inside a plan, with its rest time and one target per set.
public struct PlanExercise: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var exercise: ExerciseRef
    public var kind: TrackingKind
    public var restSeconds: Int
    public var sets: [SetValue]

    public init(id: UUID = UUID(), exercise: ExerciseRef, kind: TrackingKind, restSeconds: Int, sets: [SetValue]) {
        self.id = id
        self.exercise = exercise
        self.kind = kind
        self.restSeconds = restSeconds
        self.sets = sets
    }

    /// A new plan exercise with three sets of the default target for its kind.
    public static func make(exercise: ExerciseRef, kind: TrackingKind, restSeconds: Int, setCount: Int = 3) -> PlanExercise {
        PlanExercise(
            exercise: exercise,
            kind: kind,
            restSeconds: min(max(restSeconds, Limits.restSeconds.lowerBound), Limits.restSeconds.upperBound),
            sets: Array(repeating: .defaultValue(for: kind), count: setCount)
        )
    }

    public func validate() throws(ValidationError) {
        guard Limits.setsPerExercise.contains(sets.count) else { throw .setCount }
        guard Limits.restSeconds.contains(restSeconds) else { throw .rest }
        for set in sets {
            guard set.kind == kind else { throw .kindMismatch }
            try set.validateAsTarget()
        }
    }
}

/// A named, reusable workout template.
public struct Plan: Hashable, Codable, Sendable, Identifiable {
    public var id: PlanID
    public var name: String
    public var exercises: [PlanExercise]
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: PlanID = PlanID(), name: String, exercises: [PlanExercise] = [], createdAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public func validate() throws(ValidationError) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= Limits.nameLength.upperBound else { throw .nameTooLong }
        guard !exercises.isEmpty else { throw .noExercises }
        for exercise in exercises { try exercise.validate() }
    }

    public var isValid: Bool {
        do { try validate(); return true } catch { return false }
    }

    /// A rough length: about 4 s per rep (at least 20 s per set), timed sets as planned,
    /// plus rest after every set except the very last one.
    public var estimatedSeconds: Int {
        var total = 0
        let lastIndex = exercises.indices.last
        for (index, exercise) in exercises.enumerated() {
            for (setIndex, set) in exercise.sets.enumerated() {
                switch set {
                case .reps(let count, _): total += max(20, count * 4)
                case .duration(let seconds): total += seconds
                }
                let isLastSet = index == lastIndex && setIndex == exercise.sets.count - 1
                if !isLastSet { total += exercise.restSeconds }
            }
        }
        return total
    }

    /// A copy with fresh IDs, so the two plans never share identity.
    public func duplicated(name: String, now: Date) -> Plan {
        let exercises = exercises.map {
            PlanExercise(exercise: $0.exercise, kind: $0.kind, restSeconds: $0.restSeconds, sets: $0.sets)
        }
        return Plan(name: name, exercises: exercises, createdAt: now)
    }
}
