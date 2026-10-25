import Foundation
import Testing
@testable import AmmuttaCore

private func reps(_ count: Int, _ kg: Double?) -> SetValue {
    .reps(count: count, weight: kg.map { .kilograms($0) })
}

private func session(_ results: [SetValue], day: Int = 1) -> ExerciseSession {
    ExerciseSession(id: WorkoutID(), date: Date(timeIntervalSinceReferenceDate: Double(day) * 86_400), results: results)
}

struct OneRepMaxTests {
    @Test func usesEpleyUpToTenReps() {
        #expect(OneRepMax.estimate(reps(1, 100)) == .kilograms(100), "a single counts as itself")
        #expect(OneRepMax.estimate(reps(8, 60)) == .kilograms(76), "60 × (1 + 8/30)")
        #expect(OneRepMax.estimate(reps(10, 90)) == .kilograms(120))
        #expect(OneRepMax.estimate(reps(11, 60)) == nil, "too many reps to estimate")
        #expect(OneRepMax.estimate(reps(8, nil)) == nil, "bodyweight")
        #expect(OneRepMax.estimate(.duration(seconds: 60)) == nil)
    }
}

struct ExerciseRecordsTests {
    @Test func collectsTheBestsFromHistory() {
        let records = ExerciseRecords(sessions: [
            session([reps(5, 100), reps(5, 100)], day: 1),
            session([reps(8, 90), reps(12, 80)], day: 2),
        ])
        #expect(records.heaviest == .kilograms(100))
        #expect(records.bestEstimate == OneRepMax.estimate(reps(5, 100)), "5 × 100 beats 8 × 90")
        #expect(records.bestByReps[5] == .kilograms(100))
        #expect(records.bestByReps[8] == .kilograms(90))
        #expect(records.bestByReps[12] == nil, "only 1 to 10 reps")
        #expect(records.bestVolumeGrams == max(1_000_000, 720_000 + 960_000))
    }

    @Test func aSetBreaksOnlyRecordsThatExistAlready() {
        #expect(ExerciseRecords().broken(by: reps(5, 100)).isEmpty, "the first time sets no records")
        let records = ExerciseRecords(sessions: [session([reps(5, 100)])])
        #expect(records.broken(by: reps(5, 100)).isEmpty, "matching isn't beating")
        #expect(records.broken(by: reps(5, 102.5)) == [
            .estimate(OneRepMax.estimate(reps(5, 102.5))!), .heaviest(.kilograms(102.5)), .repBest(reps: 5, weight: .kilograms(102.5)),
        ])
        #expect(records.broken(by: reps(8, 95)) == [.estimate(OneRepMax.estimate(reps(8, 95))!)], "lighter, but a better estimate; no 8-rep best yet")
        #expect(records.broken(by: reps(8, 90)).isEmpty, "8 × 90 estimates below 5 × 100")
    }

    @Test func bodyweightAndTimedSetsHaveTheirOwnRecords() {
        let records = ExerciseRecords(sessions: [session([reps(10, nil), .duration(seconds: 45)])])
        #expect(records.broken(by: reps(12, nil)) == [.mostReps(12)])
        #expect(records.broken(by: .duration(seconds: 60)) == [.longest(seconds: 60)])
        #expect(records.broken(by: .duration(seconds: 30)).isEmpty)
    }

    @Test func aSessionKeepsTheBestRecordOfEachKind() {
        let records = ExerciseRecords(sessions: [session([reps(5, 100), reps(5, 100)])])
        let found = records.broken(bySession: [reps(5, 102.5), reps(5, 105), reps(5, 105)])
        #expect(found == [
            .estimate(OneRepMax.estimate(reps(5, 105))!), .heaviest(.kilograms(105)),
            .repBest(reps: 5, weight: .kilograms(105)), .volume(grams: 5 * (102_500 + 105_000 + 105_000)),
        ])
    }

    @Test func recordSetsCountEarlierSetsOfTheSameWorkout() {
        let records = ExerciseRecords(sessions: [session([reps(5, 100)])])
        let sets = [
            WorkoutSet(target: reps(5, 105), status: .logged(at: .now)),
            WorkoutSet(target: reps(5, 105), status: .logged(at: .now)),
            WorkoutSet(target: reps(5, 110)),
        ]
        #expect(records.recordSets(sets) == [sets[0].id], "the repeat doesn't beat the first, the pending one doesn't count")
    }

    @Test func estimatesAreChartedOldestFirst() {
        let points = ExerciseProgress.estimates([
            session([reps(5, 100)], day: 3),
            session([reps(12, 60)], day: 2),
            session([reps(8, 60), reps(1, 80)], day: 1),
        ])
        #expect(points.map { $0.estimate } == [.kilograms(80), OneRepMax.estimate(reps(5, 100))!])
    }
}
