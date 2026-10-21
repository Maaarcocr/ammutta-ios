import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func makePlan() -> Plan {
    Plan(
        name: "Push",
        exercises: [
            PlanExercise(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 90,
                         sets: [.reps(count: 8, weight: .kilograms(60)), .reps(count: 8, weight: .kilograms(60))]),
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60,
                         sets: [.duration(seconds: 45)]),
        ],
        createdAt: t0
    )
}

private func reduce(_ workout: Workout, _ events: [WorkoutEvent], at offsets: [TimeInterval]) throws -> Workout {
    var w = workout
    for (event, offset) in zip(events, offsets) {
        w = try WorkoutEngine.reduce(w, event, now: t0.addingTimeInterval(offset))
    }
    return w
}

struct WorkoutStartTests {
    @Test func startCopiesPlanAsPendingSets() {
        let plan = makePlan()
        let w = Workout.start(from: plan, now: t0)
        #expect(w.planID == plan.id)
        #expect(w.planName == "Push")
        #expect(w.exercises.count == 2)
        #expect(w.exercises.flatMap(\.sets).allSatisfy { $0.status == .pending && $0.value == $0.target })
        #expect(w.nextPendingSetID == w.exercises[0].sets[0].id)
        #expect(w.timer == nil)
    }

    @Test func customExerciseNamesAreSnapshotted() {
        let id = ExerciseID()
        let plan = Plan(name: "Mine", exercises: [.make(exercise: .custom(id), kind: .reps, restSeconds: 60)], createdAt: t0)
        let w = Workout.start(from: plan, now: t0, customNames: [id: "Landmine Press"])
        #expect(w.exercises[0].nameSnapshot == "Landmine Press")
    }
}

struct LoggingAndRestTests {
    @Test func loggingStartsRestWithTheExerciseRestTime() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let first = w0.exercises[0].sets[0].id
        let w = try WorkoutEngine.reduce(w0, .logSet(first), now: t0.addingTimeInterval(30))
        #expect(w.exercises[0].sets[0].status == .logged(at: t0.addingTimeInterval(30)))
        #expect(w.timer == .rest(afterSet: first, startedAt: t0.addingTimeInterval(30), endsAt: t0.addingTimeInterval(120)))
        #expect(w.nextPendingSetID == w0.exercises[0].sets[1].id)
    }

    @Test func loggingTheNextSetEndsRestEarlyAndStartsANewOne() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let (a, b) = (w0.exercises[0].sets[0].id, w0.exercises[0].sets[1].id)
        let w = try reduce(w0, [.logSet(a), .logSet(b)], at: [10, 40])
        #expect(w.timer == .rest(afterSet: b, startedAt: t0.addingTimeInterval(40), endsAt: t0.addingTimeInterval(130)))
    }

    @Test func loggingTheLastRemainingSetStartsNoRest() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let ids = w0.exercises.flatMap(\.sets).map(\.id)
        let w = try reduce(w0, [.logSet(ids[0]), .logSet(ids[1]), .logSet(ids[2])], at: [10, 20, 30])
        #expect(w.timer == nil)
        #expect(!w.hasPendingSets)
    }

    @Test func zeroRestStartsNoTimer() throws {
        var plan = makePlan()
        plan.exercises[0].restSeconds = 0
        let w0 = Workout.start(from: plan, now: t0)
        let w = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        #expect(w.timer == nil)
    }

    @Test func loggingTwiceIsRejected() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let id = w0.exercises[0].sets[0].id
        let w = try WorkoutEngine.reduce(w0, .logSet(id), now: t0)
        #expect(throws: WorkoutError.notAllowed) { try WorkoutEngine.reduce(w, .logSet(id), now: t0) }
    }

    @Test func restCanBeAdjustedAndSkipped() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let id = w0.exercises[0].sets[0].id
        let logged = try WorkoutEngine.reduce(w0, .logSet(id), now: t0)
        let longer = try WorkoutEngine.reduce(logged, .adjustRest(seconds: 15), now: t0.addingTimeInterval(5))
        #expect(longer.timer?.endsAt == t0.addingTimeInterval(105))
        let shorter = try WorkoutEngine.reduce(longer, .adjustRest(seconds: -15), now: t0.addingTimeInterval(5))
        #expect(shorter.timer?.endsAt == t0.addingTimeInterval(90))
        let skipped = try WorkoutEngine.reduce(shorter, .skipRest, now: t0.addingTimeInterval(6))
        #expect(skipped.timer == nil)
    }

    @Test func shorteningRestPastNowClearsIt() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        let w = try WorkoutEngine.reduce(logged, .adjustRest(seconds: -15), now: t0.addingTimeInterval(80))
        #expect(w.timer == nil)
    }

    @Test func expiredRestClearsOnlyAfterItsDeadline() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        let early = try WorkoutEngine.reduce(logged, .timerElapsed, now: t0.addingTimeInterval(89))
        #expect(early.timer != nil)
        let late = try WorkoutEngine.reduce(logged, .timerElapsed, now: t0.addingTimeInterval(90))
        #expect(late.timer == nil)
    }
}

struct DurationSetTests {
    private func atPlank() throws -> (Workout, UUID) {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let ids = w0.exercises.flatMap(\.sets).map(\.id)
        let w = try reduce(w0, [.logSet(ids[0]), .logSet(ids[1])], at: [0, 0])
        return (w, ids[2])
    }

    @Test func stoppingEarlyLogsElapsedTime() throws {
        let (w0, plank) = try atPlank()
        let running = try WorkoutEngine.reduce(w0, .startWork(plank), now: t0.addingTimeInterval(100))
        #expect(running.timer == .work(set: plank, startedAt: t0.addingTimeInterval(100), endsAt: t0.addingTimeInterval(145)))
        let stopped = try WorkoutEngine.reduce(running, .stopWork, now: t0.addingTimeInterval(130))
        let set = try #require(stopped.set(plank))
        #expect(set.value == .duration(seconds: 30))
        #expect(set.status == .logged(at: t0.addingTimeInterval(130)))
        #expect(stopped.timer == nil)
    }

    @Test func countdownReachingZeroLogsTheTargetAtItsDeadline() throws {
        let (w0, plank) = try atPlank()
        let running = try WorkoutEngine.reduce(w0, .startWork(plank), now: t0.addingTimeInterval(100))
        let done = try WorkoutEngine.reduce(running, .timerElapsed, now: t0.addingTimeInterval(150))
        let set = try #require(done.set(plank))
        #expect(set.value == .duration(seconds: 45))
        #expect(set.status == .logged(at: t0.addingTimeInterval(145)))
    }

    @Test func countdownThatEndedWhileTheAppWasDeadResolvesOnTheNextEvent() throws {
        var plan = makePlan()
        plan.exercises.append(PlanExercise(exercise: .builtIn(key: "push-up"), kind: .reps, restSeconds: 60, sets: [.reps(count: 10, weight: nil)]))
        let w0 = Workout.start(from: plan, now: t0)
        let plank = w0.exercises[1].sets[0].id
        let running = try WorkoutEngine.reduce(w0, .startWork(plank), now: t0)
        // Relaunched long after both the countdown (45 s) and its rest (60 s) ended.
        let resumed = try WorkoutEngine.reduce(running, .timerElapsed, now: t0.addingTimeInterval(600))
        #expect(resumed.set(plank)?.status == .logged(at: t0.addingTimeInterval(45)))
        #expect(resumed.timer == nil)
        // Relaunched during that rest: rest is restored from the countdown's end.
        let duringRest = try WorkoutEngine.reduce(running, .timerElapsed, now: t0.addingTimeInterval(60))
        #expect(duringRest.timer == .rest(afterSet: plank, startedAt: t0.addingTimeInterval(45), endsAt: t0.addingTimeInterval(105)))
    }

    @Test func repsSetsCannotStartACountdown() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        #expect(throws: WorkoutError.notAllowed) {
            try WorkoutEngine.reduce(w0, .startWork(w0.exercises[0].sets[0].id), now: t0)
        }
    }
}

struct EditingTests {
    @Test func valuesAreEditableBeforeAndAfterLogging() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let id = w0.exercises[0].sets[0].id
        let edited = try WorkoutEngine.reduce(w0, .setValue(id, .reps(count: 6, weight: .kilograms(62.5))), now: t0)
        let logged = try WorkoutEngine.reduce(edited, .logSet(id), now: t0)
        #expect(logged.set(id)?.value == .reps(count: 6, weight: .kilograms(62.5)))
        let fixed = try WorkoutEngine.reduce(logged, .setValue(id, .reps(count: 7, weight: .kilograms(62.5))), now: t0)
        #expect(fixed.set(id)?.value == .reps(count: 7, weight: .kilograms(62.5)))
        #expect(fixed.set(id)?.target == .reps(count: 8, weight: .kilograms(60)))
    }

    @Test func valueOfTheWrongKindIsRejected() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        #expect(throws: WorkoutError.invalidValue) {
            try WorkoutEngine.reduce(w0, .setValue(w0.exercises[0].sets[0].id, .duration(seconds: 30)), now: t0)
        }
    }

    @Test func skipAddAndRemove() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let exercise = w0.exercises[0]
        let skipped = try WorkoutEngine.reduce(w0, .skipSet(exercise.sets[0].id), now: t0)
        #expect(skipped.exercises[0].sets[0].status == .skipped(at: t0))
        #expect(skipped.nextPendingSetID == exercise.sets[1].id)

        let newID = UUID()
        let added = try WorkoutEngine.reduce(skipped, .addSet(exercise: exercise.id, newSetID: newID), now: t0)
        #expect(added.exercises[0].sets.count == 3)
        #expect(added.set(newID)?.value == exercise.sets[1].value)

        let removed = try WorkoutEngine.reduce(added, .removeSet(newID), now: t0)
        #expect(removed.exercises[0].sets.count == 2)
    }

    @Test func loggedSetsAndTheOnlySetCannotBeRemoved() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        #expect(throws: WorkoutError.notAllowed) { try WorkoutEngine.reduce(logged, .removeSet(w0.exercises[0].sets[0].id), now: t0) }
        #expect(throws: WorkoutError.notAllowed) { try WorkoutEngine.reduce(logged, .removeSet(w0.exercises[1].sets[0].id), now: t0) }
    }
}

struct FinishTests {
    @Test func finishingStopsTimersAndLocksTheWorkout() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        let finished = try WorkoutEngine.reduce(logged, .finish, now: t0.addingTimeInterval(600))
        #expect(finished.endedAt == t0.addingTimeInterval(600))
        #expect(finished.timer == nil)
        #expect(throws: WorkoutError.finished) { try WorkoutEngine.reduce(finished, .timerElapsed, now: t0) }
    }

    @Test func summaryCountsLoggedSetsAndVolume() throws {
        let w0 = Workout.start(from: makePlan(), now: t0)
        let ids = w0.exercises.flatMap(\.sets).map(\.id)
        let w = try reduce(w0, [.logSet(ids[0]), .skipSet(ids[1]), .finish], at: [60, 120, 1800])
        let summary = WorkoutSummary(w)
        #expect(summary.durationSeconds == 1800)
        #expect(summary.loggedSets == 1)
        #expect(summary.skippedSets == 1)
        #expect(summary.totalSets == 3)
        #expect(summary.volumeGrams == 8 * 60_000)
    }
}
