import AmmuttaCore
import Foundation
import Testing
@testable import AmmuttaPersistence

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func samplePlan(name: String = "Push") -> Plan {
    Plan(name: name, exercises: [
        PlanExercise(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 90,
                     sets: [.reps(count: 5, weight: .kilograms(80)), .reps(count: 3, weight: .kilograms(85))]),
    ], createdAt: t0)
}

@MainActor
struct AmmuttaStoreTests {
    @Test func plansRoundTripAndUpdateInPlace() throws {
        let store = try AmmuttaStore(inMemory: true)
        var plan = samplePlan()
        try store.save(plan)
        #expect(try store.plans() == [plan])

        plan.name = "Push A"
        plan.exercises[0].sets.append(.reps(count: 1, weight: .kilograms(90)))
        try store.save(plan)
        #expect(try store.plans() == [plan])

        try store.deletePlan(plan.id)
        #expect(try store.plans().isEmpty)
    }

    @Test func customExercisesRoundTrip() throws {
        let store = try AmmuttaStore(inMemory: true)
        var exercise = CustomExercise(name: "Landmine Press", kind: .reps, createdAt: t0)
        try store.save(exercise)
        exercise.name = "Landmine press"
        try store.save(exercise)
        #expect(try store.customExercises() == [exercise])
        try store.deleteCustomExercise(exercise.id)
        #expect(try store.customExercises().isEmpty)
    }

    @Test func activeWorkoutIsSavedAfterEveryEventAndReloaded() throws {
        let store = try AmmuttaStore(inMemory: true)
        var workout = Workout.start(from: samplePlan(), now: t0)
        try store.save(workout)
        workout = try WorkoutEngine.reduce(workout, .logSet(workout.exercises[0].sets[0].id), now: t0.addingTimeInterval(30))
        try store.save(workout)

        let reloaded = try #require(try store.activeWorkout())
        #expect(reloaded == workout)
        #expect(reloaded.timer != nil)
        #expect(try store.completedWorkouts().isEmpty)
    }

    @Test func onlyOneWorkoutCanBeActive() throws {
        let store = try AmmuttaStore(inMemory: true)
        try store.save(Workout.start(from: samplePlan(), now: t0))
        #expect(throws: StoreError.anotherWorkoutActive) {
            try store.save(Workout.start(from: samplePlan(), now: t0.addingTimeInterval(10)))
        }
    }

    @Test func finishedWorkoutsMoveToHistoryNewestFirst() throws {
        let store = try AmmuttaStore(inMemory: true)
        for offset in [0.0, 86_400] {
            let started = Workout.start(from: samplePlan(), now: t0.addingTimeInterval(offset))
            try store.save(started)
            try store.save(try WorkoutEngine.reduce(started, .finish, now: t0.addingTimeInterval(offset + 3600)))
        }
        let history = try store.completedWorkouts()
        #expect(history.count == 2)
        #expect(history[0].startedAt > history[1].startedAt)
        #expect(try store.activeWorkout() == nil)

        try store.deleteWorkout(history[0].id)
        #expect(try store.completedWorkouts().count == 1)
    }

    @Test func deletingAPlanKeepsItsHistory() throws {
        let store = try AmmuttaStore(inMemory: true)
        let plan = samplePlan()
        try store.save(plan)
        let workout = try WorkoutEngine.reduce(Workout.start(from: plan, now: t0), .finish, now: t0.addingTimeInterval(60))
        try store.save(workout)
        try store.deletePlan(plan.id)
        #expect(try store.completedWorkouts().map(\.planName) == ["Push"])
    }
}
