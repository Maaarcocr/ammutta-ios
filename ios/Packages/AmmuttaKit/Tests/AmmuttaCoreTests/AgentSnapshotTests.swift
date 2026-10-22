import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct AgentSnapshotTests {
    private let band = CustomExercise(name: "Band Pull-Apart", kind: .reps, createdAt: t0)

    private func plan() -> Plan {
        Plan(name: "Push", exercises: [
            PlanExercise(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 150,
                         sets: [.reps(count: 8, weight: .kilograms(60)), .reps(count: 8, weight: .kilograms(60))]),
            PlanExercise(exercise: band.ref, kind: .reps, restSeconds: 60, sets: [.reps(count: 15, weight: nil)]),
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60, sets: [.duration(seconds: 45)]),
        ], createdAt: t0)
    }

    private func snapshot(unit: WeightUnit = .kilograms, workouts: [Workout] = []) -> AgentSnapshot {
        AgentSnapshot(plans: [plan()], workouts: workouts, customExercises: [band], unit: unit, now: t0) { "EN:" + $0 }
    }

    @Test func plansUseBuiltInKeysCustomNamesAndLinkSetSyntax() {
        let exercises = snapshot().plans[0].exercises
        #expect(exercises.map(\.exercise) == ["barbell-bench-press", "Band Pull-Apart", "plank"])
        #expect(exercises.map(\.name) == ["EN:barbell-bench-press", "Band Pull-Apart", "EN:plank"])
        #expect(exercises.map(\.sets) == ["2x8@60", "15", "45s"])
        #expect(snapshot(unit: .pounds).plans[0].exercises[0].sets.hasPrefix("2x8@132"))
    }

    @Test func workoutsListFinishedOnesNewestFirstWithSetResults() throws {
        var older = Workout.start(from: plan(), now: t0, customNames: [band.id: band.name])
        let first = try #require(older.nextPendingSetID)
        older = try WorkoutEngine.reduce(older, .logSet(first), now: t0.addingTimeInterval(60))
        older = try WorkoutEngine.reduce(older, .finish, now: t0.addingTimeInterval(1_800))
        var newer = Workout.start(from: plan(), now: t0.addingTimeInterval(86_400))
        newer.endedAt = t0.addingTimeInterval(90_000)
        let active = Workout.start(from: plan(), now: t0.addingTimeInterval(200_000))

        let workouts = snapshot(workouts: [older, active, newer]).workouts
        #expect(workouts.map(\.id) == [newer.id.rawValue.uuidString, older.id.rawValue.uuidString])
        let bench = workouts[1].exercises[0]
        #expect(bench.exercise == "barbell-bench-press")
        #expect(bench.sets.map(\.status) == ["done", "not done"])
        #expect(bench.sets[0].reps == 8)
        #expect(bench.sets[0].weight == 60)
        #expect(workouts[1].durationMinutes == 30)
    }

    @Test func listsEveryBuiltInExercise() {
        let builtIns = snapshot().builtInExercises
        #expect(builtIns.count == ExerciseCatalog.all.count)
        #expect(builtIns.first { $0.key == "plank" }?.kind == "timed")
    }

    @Test func encodesToJSON() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = snapshot()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(AgentSnapshot.self, from: data) == original)
    }
}
