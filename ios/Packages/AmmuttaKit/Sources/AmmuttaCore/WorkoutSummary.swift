import Foundation

public struct WorkoutSummary: Equatable, Sendable {
    public var durationSeconds: Int
    public var loggedSets: Int
    public var skippedSets: Int
    public var totalSets: Int
    /// Σ reps × weight, in grams.
    public var volumeGrams: Int

    public init(_ workout: Workout, now: Date = Date()) {
        let end = workout.endedAt ?? now
        durationSeconds = max(0, Int(end.timeIntervalSince(workout.startedAt).rounded()))
        let sets = workout.exercises.flatMap(\.sets)
        loggedSets = sets.count(where: { $0.status.isLogged })
        skippedSets = sets.count(where: { $0.status.isSkipped })
        totalSets = sets.count
        volumeGrams = sets.filter { $0.status.isLogged }.reduce(0) { $0 + $1.value.volumeGrams }
    }
}

/// One past workout's logged sets for a single exercise.
public struct ExerciseSession: Equatable, Sendable, Identifiable {
    public var id: WorkoutID
    public var date: Date
    public var results: [SetValue]
}

public enum ExerciseProgress {
    /// Completed sessions that logged at least one set of `ref`, newest first.
    public static func sessions(of ref: ExerciseRef, in workouts: [Workout]) -> [ExerciseSession] {
        workouts
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
            .compactMap { workout in
                let results = workout.exercises
                    .filter { $0.exercise == ref }
                    .flatMap(\.sets)
                    .filter { $0.status.isLogged }
                    .map(\.value)
                return results.isEmpty ? nil : ExerciseSession(id: workout.id, date: workout.startedAt, results: results)
            }
    }

    public static func lastPerformance(of ref: ExerciseRef, in workouts: [Workout]) -> ExerciseSession? {
        sessions(of: ref, in: workouts).first
    }
}
