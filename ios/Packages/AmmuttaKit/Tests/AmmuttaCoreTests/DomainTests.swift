import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct MassTests {
    @Test func kilogramsAreStoredAsGramsInQuarterSteps() {
        #expect(Mass.kilograms(62.5).grams == 62_500)
        #expect(Mass.kilograms(62.6).grams == 62_500)
        #expect(Mass.kilograms(1.25).grams == 1_250)
    }

    @Test func poundsRoundTripThroughGrams() {
        for pounds in [0.25, 45, 135, 225.5, 405] {
            #expect(Mass.pounds(pounds).value(in: .pounds) == pounds)
        }
    }

    @Test func addingClampsToTheAllowedRange() {
        #expect(Mass.kilograms(1).adding(-2.5, unit: .kilograms) == .zero)
        #expect(Mass.kilograms(999).adding(2.5, unit: .kilograms).grams == Limits.weightGrams.upperBound)
        #expect(Mass.kilograms(60).adding(2.5, unit: .kilograms) == .kilograms(62.5))
    }
}

struct PlanValidationTests {
    private func validPlan() -> Plan {
        Plan(name: "Legs", exercises: [.make(exercise: .builtIn(key: "barbell-back-squat"), kind: .reps, restSeconds: 120)], createdAt: t0)
    }

    @Test func validPlanPasses() throws {
        try validPlan().validate()
        #expect(validPlan().isValid)
    }

    @Test func invalidPlansAreRejected() {
        var blank = validPlan(); blank.name = "   "
        #expect(throws: ValidationError.emptyName) { try blank.validate() }

        var empty = validPlan(); empty.exercises = []
        #expect(throws: ValidationError.noExercises) { try empty.validate() }

        var tooManySets = validPlan(); tooManySets.exercises[0].sets = Array(repeating: .reps(count: 5, weight: nil), count: 21)
        #expect(throws: ValidationError.setCount) { try tooManySets.validate() }

        var badReps = validPlan(); badReps.exercises[0].sets[0] = .reps(count: 0, weight: nil)
        #expect(throws: ValidationError.reps) { try badReps.validate() }

        var heavy = validPlan(); heavy.exercises[0].sets[0] = .reps(count: 5, weight: Mass(grams: 1_000_000))
        #expect(throws: ValidationError.weight) { try heavy.validate() }

        var wrongKind = validPlan(); wrongKind.exercises[0].sets[0] = .duration(seconds: 30)
        #expect(throws: ValidationError.kindMismatch) { try wrongKind.validate() }

        var longRest = validPlan(); longRest.exercises[0].restSeconds = 601
        #expect(throws: ValidationError.rest) { try longRest.validate() }
    }

    @Test func durationTargetsMustBeAtLeastFiveSeconds() {
        #expect(throws: ValidationError.duration) { try SetValue.duration(seconds: 4).validateAsTarget() }
        #expect(throws: Never.self) { try SetValue.duration(seconds: 4).validateAsResult() }
    }

    @Test func estimatedDurationCountsRestBetweenSetsOnly() {
        let plan = Plan(name: "x", exercises: [
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60, sets: [.duration(seconds: 30), .duration(seconds: 30)]),
        ], createdAt: t0)
        #expect(plan.estimatedSeconds == 30 + 60 + 30)
    }

    @Test func duplicateGetsFreshIdentity() {
        let plan = validPlan()
        let copy = plan.duplicated(name: "Legs (copy)", now: t0)
        #expect(copy.id != plan.id)
        #expect(copy.exercises[0].id != plan.exercises[0].id)
        #expect(copy.exercises[0].sets == plan.exercises[0].sets)
    }
}

struct ExerciseTests {
    @Test func catalogKeysAreUniqueAndStable() {
        let keys = ExerciseCatalog.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(keys.count >= 80)
        // Keys from the first release must never disappear: saved plans and shared links use them.
        let original = [
            "barbell-bench-press", "barbell-back-squat", "barbell-deadlift", "barbell-overhead-press", "barbell-row",
            "barbell-romanian-deadlift", "barbell-hip-thrust", "dumbbell-bench-press", "dumbbell-shoulder-press",
            "dumbbell-row", "dumbbell-curl", "dumbbell-lateral-raise", "dumbbell-lunge", "kettlebell-goblet-squat",
            "kettlebell-swing", "pull-up", "chin-up", "push-up", "dip", "bodyweight-squat", "lat-pulldown",
            "seated-cable-row", "triceps-pushdown", "leg-press", "leg-curl", "crunch", "hanging-leg-raise",
            "plank", "side-plank", "wall-sit", "dead-hang", "jump-rope",
        ]
        #expect(original.allSatisfy { ExerciseCatalog.exercise(forKey: $0) != nil })
        #expect(ExerciseCatalog.exercise(forKey: "plank")?.kind == .duration)
        #expect(keys.allSatisfy { $0.allSatisfy { $0.isLowercase || $0 == "-" } })
    }

    @Test func duplicateNamesIgnoreCaseAccentsAndSpaces() {
        let existing = ["Panca piana", "Curl con manubri"]
        #expect(ExerciseNames.isDuplicate("  PANCA PIANA ", among: existing))
        #expect(ExerciseNames.isDuplicate("cúrl con manubri", among: existing))
        #expect(!ExerciseNames.isDuplicate("Panca inclinata", among: existing))
        #expect(!ExerciseNames.isDuplicate("   ", among: existing))
    }
}

struct ProgressTests {
    @Test func lastPerformanceIsTheNewestCompletedSession() throws {
        let plan = Plan(name: "Push", exercises: [
            PlanExercise(exercise: .builtIn(key: "push-up"), kind: .reps, restSeconds: 0, sets: [.reps(count: 10, weight: nil)]),
        ], createdAt: t0)
        func completed(at offset: TimeInterval, reps: Int) throws -> Workout {
            let start = t0.addingTimeInterval(offset)
            var w = Workout.start(from: plan, now: start)
            let id = w.exercises[0].sets[0].id
            w = try WorkoutEngine.reduce(w, .setValue(id, .reps(count: reps, weight: nil)), now: start)
            w = try WorkoutEngine.reduce(w, .logSet(id), now: start)
            return try WorkoutEngine.reduce(w, .finish, now: start.addingTimeInterval(60))
        }
        let older = try completed(at: 0, reps: 10)
        let newer = try completed(at: 86_400, reps: 12)
        let active = Workout.start(from: plan, now: t0.addingTimeInterval(200_000))

        let last = try #require(ExerciseProgress.lastPerformance(of: .builtIn(key: "push-up"), in: [older, active, newer]))
        #expect(last.id == newer.id)
        #expect(last.results == [.reps(count: 12, weight: nil)])
        #expect(ExerciseProgress.sessions(of: .builtIn(key: "push-up"), in: [older, newer]).count == 2)
        #expect(ExerciseProgress.lastPerformance(of: .builtIn(key: "plank"), in: [older, newer]) == nil)
    }
}
