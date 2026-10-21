import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct TimerAlertPlanTests {
    private func workout() -> Workout {
        Workout.start(from: Plan(name: "x", exercises: [
            PlanExercise(exercise: .builtIn(key: "push-up"), kind: .reps, restSeconds: 90, sets: [.reps(count: 10, weight: nil), .reps(count: 10, weight: nil)]),
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60, sets: [.duration(seconds: 45)]),
        ], createdAt: t0), now: t0)
    }

    @Test func noTimerMeansNoAlert() {
        #expect(workout().pendingTimerAlert(now: t0) == nil)
    }

    @Test func restAlertFiresAtTheDeadlineAndNamesTheNextSet() throws {
        let w0 = workout()
        let w = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        #expect(w.pendingTimerAlert(now: t0) ==
            TimerAlertPlan(fireDate: t0.addingTimeInterval(90), kind: .restOver(nextSet: w0.exercises[0].sets[1].id)))
    }

    @Test func adjustingRestMovesTheAlertAndSkippingRemovesIt() throws {
        let w0 = workout()
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        let longer = try WorkoutEngine.reduce(logged, .adjustRest(seconds: 15), now: t0)
        #expect(longer.pendingTimerAlert(now: t0)?.fireDate == t0.addingTimeInterval(105))
        let skipped = try WorkoutEngine.reduce(longer, .skipRest, now: t0)
        #expect(skipped.pendingTimerAlert(now: t0) == nil)
    }

    @Test func timedSetAlertsWhenItsCountdownEnds() throws {
        let w0 = workout()
        let plank = w0.exercises[1].sets[0].id
        let running = try WorkoutEngine.reduce(w0, .startWork(plank), now: t0)
        #expect(running.pendingTimerAlert(now: t0) == TimerAlertPlan(fireDate: t0.addingTimeInterval(45), kind: .workDone(set: plank)))
    }

    @Test func passedDeadlinesAndFinishedWorkoutsHaveNoAlert() throws {
        let w0 = workout()
        let logged = try WorkoutEngine.reduce(w0, .logSet(w0.exercises[0].sets[0].id), now: t0)
        #expect(logged.pendingTimerAlert(now: t0.addingTimeInterval(90)) == nil)
        let finished = try WorkoutEngine.reduce(logged, .finish, now: t0.addingTimeInterval(10))
        #expect(finished.pendingTimerAlert(now: t0.addingTimeInterval(10)) == nil)
    }
}
