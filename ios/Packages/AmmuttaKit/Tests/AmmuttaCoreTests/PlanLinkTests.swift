import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct PlanLinkParsingTests {
    @Test func parsesTheDocumentedExample() throws {
        let draft = try PlanLink.parse(
            "ammutta://plan?v=1&name=Push%20Day&e=barbell-bench-press:3x8@60:150&e=Face%20Pull:3x15@12.5:60&e=plank:2x45s"
        )
        #expect(draft.name == "Push Day")
        #expect(draft.exercises.count == 3)

        let bench = draft.exercises[0]
        #expect(bench.reference == .builtIn(key: "barbell-bench-press"))
        #expect(bench.kind == .reps)
        #expect(bench.restSeconds == 150)
        #expect(bench.sets == Array(repeating: .reps(count: 8, weight: .kilograms(60)), count: 3))

        #expect(draft.exercises[1].reference == .named("Face Pull"))
        #expect(draft.exercises[1].sets.first == .reps(count: 15, weight: .kilograms(12.5)))

        let plank = draft.exercises[2]
        #expect(plank.kind == .duration)
        #expect(plank.restSeconds == nil)
        #expect(plank.sets == [.duration(seconds: 45), .duration(seconds: 45)])
    }

    @Test func perSetTargetsAndMixedShorthand() throws {
        let draft = try PlanLink.parse("ammutta://plan?v=1&name=Pyramid&e=barbell-back-squat:2x5@100,3@110,1@120:3m")
        #expect(draft.exercises[0].sets == [
            .reps(count: 5, weight: .kilograms(100)), .reps(count: 5, weight: .kilograms(100)),
            .reps(count: 3, weight: .kilograms(110)), .reps(count: 1, weight: .kilograms(120)),
        ])
        #expect(draft.exercises[0].restSeconds == 180)
    }

    @Test func bodyweightRepsAndDurationsInMinutes() throws {
        let draft = try PlanLink.parse("ammutta://plan?v=1&name=Core&e=pull-up:3x8:90&e=wall-sit:1m30s,2m:60")
        #expect(draft.exercises[0].sets.allSatisfy { $0 == .reps(count: 8, weight: nil) })
        #expect(draft.exercises[1].sets == [.duration(seconds: 90), .duration(seconds: 120)])
    }

    @Test func poundsAreConvertedToGrams() throws {
        let draft = try PlanLink.parse("ammutta://plan?v=1&unit=lb&name=US&e=barbell-deadlift:5@225")
        #expect(draft.exercises[0].sets == [.reps(count: 5, weight: .pounds(225))])
    }

    @Test func pastedLinksAreForgiving() throws {
        // Surrounding whitespace, unencoded spaces, upper-case keys and scheme.
        let draft = try PlanLink.parse("  AMMUTTA://plan?v=1&name=Leg Day&e=Barbell-Back-Squat: 3x5@100 : 180 \n")
        #expect(draft.name == "Leg Day")
        #expect(draft.exercises[0].reference == .builtIn(key: "barbell-back-squat"))
        #expect(draft.exercises[0].sets.count == 3)
    }

    @Test func accentedNamesCanBeWrittenDirectly() throws {
        let draft = try PlanLink.parse("ammutta://plan?v=1&name=Forza è vita&e=Alzate frontali:3x12@8:60")
        #expect(draft.name == "Forza è vita")
        #expect(draft.exercises[0].reference == .named("Alzate frontali"))
        let encoded = try PlanLink.parse("ammutta://plan?v=1&name=Forza%20%C3%A8%20vita&e=plank:30s")
        #expect(encoded.name == "Forza è vita")
    }

    @Test func zeroWeightMeansBodyweight() throws {
        let draft = try PlanLink.parse("ammutta://plan?v=1&name=X&e=dip:10@0")
        #expect(draft.exercises[0].sets == [.reps(count: 10, weight: nil)])
    }

    @Test func invalidLinksAreRejectedWithoutPartialResults() {
        let cases: [(String, PlanLink.ParseError)] = [
            ("https://example.com/plan?v=1&name=X&e=plank:30s", .notAPlanLink),
            ("ammutta://workout?v=1&name=X&e=plank:30s", .notAPlanLink),
            ("ammutta://plan?name=X&e=plank:30s", .unsupportedVersion),
            ("ammutta://plan?v=2&name=X&e=plank:30s", .unsupportedVersion),
            ("ammutta://plan?v=1&unit=stone&name=X&e=plank:30s", .invalidUnit),
            ("ammutta://plan?v=1&name=%20&e=plank:30s", .missingName),
            ("ammutta://plan?v=1&name=X", .noExercises),
            ("ammutta://plan?v=1&name=X&e=plank", .invalidExercise(1)),
            ("ammutta://plan?v=1&name=X&e=push-up:10&e=plank:10", .invalidExercise(2)),       // built-in kind mismatch
            ("ammutta://plan?v=1&name=X&e=Custom:10,30s", .invalidExercise(1)),               // mixed kinds
            ("ammutta://plan?v=1&name=X&e=plank:3s", .invalidExercise(1)),                    // under 5 s
            ("ammutta://plan?v=1&name=X&e=push-up:0", .invalidExercise(1)),                   // zero reps
            ("ammutta://plan?v=1&name=X&e=push-up:21x10", .invalidExercise(1)),               // too many sets
            ("ammutta://plan?v=1&name=X&e=push-up:10:601", .invalidExercise(1)),              // rest over 10 min
            ("ammutta://plan?v=1&name=X&e=push-up:10@abc", .invalidExercise(1)),
            ("ammutta://plan?v=1&name=X&e=barbell-deadlift:5@1000", .invalidExercise(1)),     // over 999.75 kg
            ("ammutta://plan?v=1&name=X&e=push-up:10:90:extra", .invalidExercise(1)),
        ]
        for (link, expected) in cases {
            #expect(throws: expected, "\(link)") { try PlanLink.parse(link) }
        }
    }

    @Test func limitsOnSizeAndExerciseCount() {
        let many = (1...31).map { _ in "e=plank:30s" }.joined(separator: "&")
        #expect(throws: PlanLink.ParseError.tooManyExercises) { try PlanLink.parse("ammutta://plan?v=1&name=X&\(many)") }
        let long = "ammutta://plan?v=1&name=" + String(repeating: "a", count: 9_000) + "&e=plank:30s"
        #expect(throws: PlanLink.ParseError.tooLong) { try PlanLink.parse(long) }
    }

    @Test func durationTokens() {
        #expect(PlanLink.parseDuration("45s") == 45)
        #expect(PlanLink.parseDuration("2m") == 120)
        #expect(PlanLink.parseDuration("1m30s") == 90)
        #expect(PlanLink.parseDuration("90") == nil)
        #expect(PlanLink.parseDuration("s") == nil)
        #expect(PlanLink.parseDuration("1s2m") == nil)
    }
}

struct PlanLinkEncodingTests {
    private func samplePlan(customID: ExerciseID, unit: WeightUnit = .kilograms) -> Plan {
        Plan(name: "Push & Pull", exercises: [
            PlanExercise(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 150,
                         sets: [.reps(count: 8, weight: Mass(60, unit: unit)), .reps(count: 8, weight: Mass(60, unit: unit)),
                                .reps(count: 6, weight: Mass(62.5, unit: unit))]),
            PlanExercise(exercise: .custom(customID), kind: .reps, restSeconds: 60,
                         sets: Array(repeating: .reps(count: 12, weight: nil), count: 3)),
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60,
                         sets: [.duration(seconds: 45), .duration(seconds: 90)]),
        ], createdAt: t0)
    }

    @Test func encodesReadableCompactLinks() throws {
        let id = ExerciseID()
        let url = try #require(PlanLink.url(for: samplePlan(customID: id), customNames: [id: "Band Pull-Apart"]))
        #expect(url.absoluteString ==
            "ammutta://plan?v=1&name=Push%20%26%20Pull" +
            "&e=barbell-bench-press:2x8@60,6@62.5:150&e=Band%20Pull-Apart:3x12:60&e=plank:45s,1m30s:60")
    }

    @Test func roundTripsThroughParsing() throws {
        let id = ExerciseID()
        let plan = samplePlan(customID: id, unit: unit)
        for unit in WeightUnit.allCases {
            let url = try #require(PlanLink.url(for: plan, customNames: [id: "Band Pull-Apart"], unit: unit))
            let draft = try PlanLink.parse(url)
            #expect(draft.name == plan.name)
            #expect(draft.exercises.map(\.sets) == plan.exercises.map(\.sets))
            #expect(draft.exercises.map(\.restSeconds) == plan.exercises.map { $0.restSeconds })
            #expect(draft.exercises[1].reference == .named("Band Pull-Apart"))
        }
    }

    @Test func missingCustomNameYieldsNoLink() {
        #expect(PlanLink.url(for: samplePlan(customID: ExerciseID()), customNames: [:]) == nil)
    }
}
