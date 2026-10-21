import Foundation

/// The built-in exercises. Display names live in the app's Exercises string catalog
/// under "exercise.<key>"; keys are stable forever because plans reference them.
public enum ExerciseCatalog {
    public static let all: [BuiltInExercise] = [
        // Barbell
        .init("barbell-bench-press", .reps, .barbell, .chest),
        .init("barbell-back-squat", .reps, .barbell, .legs),
        .init("barbell-deadlift", .reps, .barbell, .back),
        .init("barbell-overhead-press", .reps, .barbell, .shoulders),
        .init("barbell-row", .reps, .barbell, .back),
        .init("barbell-romanian-deadlift", .reps, .barbell, .legs),
        .init("barbell-hip-thrust", .reps, .barbell, .glutes),
        // Dumbbell
        .init("dumbbell-bench-press", .reps, .dumbbell, .chest),
        .init("dumbbell-shoulder-press", .reps, .dumbbell, .shoulders),
        .init("dumbbell-row", .reps, .dumbbell, .back),
        .init("dumbbell-curl", .reps, .dumbbell, .arms),
        .init("dumbbell-lateral-raise", .reps, .dumbbell, .shoulders),
        .init("dumbbell-lunge", .reps, .dumbbell, .legs),
        // Kettlebell
        .init("kettlebell-goblet-squat", .reps, .kettlebell, .legs),
        .init("kettlebell-swing", .reps, .kettlebell, .glutes),
        // Bodyweight
        .init("pull-up", .reps, .bodyweight, .back),
        .init("chin-up", .reps, .bodyweight, .back),
        .init("push-up", .reps, .bodyweight, .chest),
        .init("dip", .reps, .bodyweight, .arms),
        .init("bodyweight-squat", .reps, .bodyweight, .legs),
        // Cable and machine
        .init("lat-pulldown", .reps, .cable, .back),
        .init("seated-cable-row", .reps, .cable, .back),
        .init("triceps-pushdown", .reps, .cable, .arms),
        .init("leg-press", .reps, .machine, .legs),
        .init("leg-curl", .reps, .machine, .legs),
        // Core
        .init("crunch", .reps, .bodyweight, .core),
        .init("hanging-leg-raise", .reps, .bodyweight, .core),
        // Timed
        .init("plank", .duration, .bodyweight, .core),
        .init("side-plank", .duration, .bodyweight, .core),
        .init("wall-sit", .duration, .bodyweight, .legs),
        .init("dead-hang", .duration, .bodyweight, .back),
        .init("jump-rope", .duration, .other, .fullBody),
    ]

    private static let byKey: [String: BuiltInExercise] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static func exercise(forKey key: String) -> BuiltInExercise? { byKey[key] }
}
