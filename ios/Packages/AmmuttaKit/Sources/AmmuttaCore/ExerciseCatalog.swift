import Foundation

/// The built-in exercises. Names, technique tips and muscles worked live in the app's
/// Exercises string catalog under "exercise.<key>", "tip.<key>" and "muscles.<key>".
/// Keys are stable forever because plans and plan links reference them.
public enum ExerciseCatalog {
    public static let all: [BuiltInExercise] = [
        // Barbell
        .init("barbell-bench-press", .reps, .barbell, .chest),
        .init("incline-barbell-bench-press", .reps, .barbell, .chest),
        .init("close-grip-bench-press", .reps, .barbell, .arms),
        .init("barbell-back-squat", .reps, .barbell, .legs),
        .init("barbell-front-squat", .reps, .barbell, .legs),
        .init("barbell-deadlift", .reps, .barbell, .back),
        .init("sumo-deadlift", .reps, .barbell, .legs),
        .init("barbell-romanian-deadlift", .reps, .barbell, .legs),
        .init("good-morning", .reps, .barbell, .legs),
        .init("barbell-hip-thrust", .reps, .barbell, .glutes),
        .init("barbell-overhead-press", .reps, .barbell, .shoulders),
        .init("barbell-row", .reps, .barbell, .back),
        .init("barbell-shrug", .reps, .barbell, .back),
        .init("barbell-curl", .reps, .barbell, .arms),
        // Dumbbell
        .init("dumbbell-bench-press", .reps, .dumbbell, .chest),
        .init("incline-dumbbell-bench-press", .reps, .dumbbell, .chest),
        .init("dumbbell-fly", .reps, .dumbbell, .chest),
        .init("dumbbell-shoulder-press", .reps, .dumbbell, .shoulders),
        .init("arnold-press", .reps, .dumbbell, .shoulders),
        .init("dumbbell-lateral-raise", .reps, .dumbbell, .shoulders),
        .init("rear-delt-fly", .reps, .dumbbell, .shoulders),
        .init("dumbbell-row", .reps, .dumbbell, .back),
        .init("dumbbell-curl", .reps, .dumbbell, .arms),
        .init("hammer-curl", .reps, .dumbbell, .arms),
        .init("dumbbell-triceps-extension", .reps, .dumbbell, .arms),
        .init("dumbbell-romanian-deadlift", .reps, .dumbbell, .legs),
        .init("dumbbell-lunge", .reps, .dumbbell, .legs),
        .init("bulgarian-split-squat", .reps, .dumbbell, .legs),
        // Kettlebell
        .init("kettlebell-goblet-squat", .reps, .kettlebell, .legs),
        .init("kettlebell-swing", .reps, .kettlebell, .glutes),
        // Bodyweight
        .init("push-up", .reps, .bodyweight, .chest),
        .init("pull-up", .reps, .bodyweight, .back),
        .init("chin-up", .reps, .bodyweight, .back),
        .init("inverted-row", .reps, .bodyweight, .back),
        .init("dip", .reps, .bodyweight, .arms),
        .init("bodyweight-squat", .reps, .bodyweight, .legs),
        .init("walking-lunge", .reps, .bodyweight, .legs),
        .init("step-up", .reps, .bodyweight, .legs),
        .init("burpee", .reps, .bodyweight, .fullBody),
        .init("crunch", .reps, .bodyweight, .core),
        .init("sit-up", .reps, .bodyweight, .core),
        .init("leg-raise", .reps, .bodyweight, .core),
        .init("hanging-knee-raise", .reps, .bodyweight, .core),
        .init("hanging-leg-raise", .reps, .bodyweight, .core),
        .init("back-extension", .reps, .other, .back),
        // Cable
        .init("lat-pulldown", .reps, .cable, .back),
        .init("seated-cable-row", .reps, .cable, .back),
        .init("cable-face-pull", .reps, .cable, .shoulders),
        .init("triceps-pushdown", .reps, .cable, .arms),
        .init("cable-overhead-triceps-extension", .reps, .cable, .arms),
        .init("cable-curl", .reps, .cable, .arms),
        .init("cable-woodchop", .reps, .cable, .core),
        // Machine
        .init("machine-chest-press", .reps, .machine, .chest),
        .init("pec-deck", .reps, .machine, .chest),
        .init("machine-shoulder-press", .reps, .machine, .shoulders),
        .init("assisted-pull-up", .reps, .machine, .back),
        .init("assisted-dip", .reps, .machine, .arms),
        .init("leg-press", .reps, .machine, .legs),
        .init("hack-squat", .reps, .machine, .legs),
        .init("smith-machine-squat", .reps, .machine, .legs),
        .init("leg-extension", .reps, .machine, .legs),
        .init("leg-curl", .reps, .machine, .legs),
        .init("lying-leg-curl", .reps, .machine, .legs),
        .init("standing-calf-raise", .reps, .machine, .legs),
        .init("seated-calf-raise", .reps, .machine, .legs),
        .init("hip-abductor", .reps, .machine, .glutes),
        .init("hip-adductor", .reps, .machine, .legs),
        // Timed
        .init("plank", .duration, .bodyweight, .core),
        .init("side-plank", .duration, .bodyweight, .core),
        .init("bear-plank", .duration, .bodyweight, .core),
        .init("hollow-hold", .duration, .bodyweight, .core),
        .init("l-sit", .duration, .bodyweight, .core),
        .init("wall-sit", .duration, .bodyweight, .legs),
        .init("glute-bridge-hold", .duration, .bodyweight, .glutes),
        .init("superman-hold", .duration, .bodyweight, .back),
        .init("dead-hang", .duration, .bodyweight, .back),
        .init("mountain-climbers", .duration, .bodyweight, .fullBody),
        .init("high-knees", .duration, .bodyweight, .fullBody),
        .init("bear-crawl", .duration, .bodyweight, .fullBody),
        .init("jump-rope", .duration, .other, .fullBody),
        .init("battle-ropes", .duration, .other, .fullBody),
    ]

    private static let byKey: [String: BuiltInExercise] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static func exercise(forKey key: String) -> BuiltInExercise? { byKey[key] }
}
