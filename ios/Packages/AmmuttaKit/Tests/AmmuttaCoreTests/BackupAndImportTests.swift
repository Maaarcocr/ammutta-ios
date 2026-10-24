import Foundation
import Testing
@testable import AmmuttaCore

private let utc = TimeZone(identifier: "UTC")!

private func date(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = utc
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: text)!
}

struct BackupTests {
    private func backup() throws -> AmmuttaBackup {
        let plan = Plan(name: "Push", exercises: [.make(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 90)], createdAt: date("2026-01-01 10:00"))
        let finished = try WorkoutEngine.reduce(Workout.start(from: plan, now: date("2026-01-02 10:00")), .finish, now: date("2026-01-02 11:00"))
        let active = Workout.start(from: plan, now: date("2026-01-03 10:00"))
        return AmmuttaBackup(
            exportedAt: date("2026-01-03 12:00"), weightUnit: .pounds, defaultRestSeconds: 120,
            customExercises: [CustomExercise(name: "Band Pull-Apart", kind: .reps, createdAt: date("2026-01-01 09:00"))],
            plans: [plan], workouts: [finished, active]
        )
    }

    @Test func roundTripsAndLeavesOutTheActiveWorkout() throws {
        let original = try backup()
        #expect(original.workouts.count == 1)
        let read = try AmmuttaBackup.decode(try original.encoded())
        #expect(read == original)
        #expect(read.version == AmmuttaBackup.currentVersion)
    }

    @Test func refusesOtherFilesAndNewerVersions() throws {
        #expect(throws: AmmuttaBackup.ReadError.notABackup) { try AmmuttaBackup.decode(Data("{\"title\":\"x\"}".utf8)) }
        #expect(throws: AmmuttaBackup.ReadError.notABackup) { try AmmuttaBackup.decode(Data("not json".utf8)) }
        var newer = try backup()
        newer.version = AmmuttaBackup.currentVersion + 1
        let data = try newer.encoded()
        #expect(throws: AmmuttaBackup.ReadError.newerVersion) { try AmmuttaBackup.decode(data) }
    }
}

struct HistoryCSVTests {
    @Test func readsAStrongExport() throws {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\r
        2020-12-30 18:51:52,"Evening Workout",1h 5m,"Bench Press (Barbell)",1,60.0,8,0,0,"felt ""good""","",\r
        2020-12-30 18:51:52,"Evening Workout",1h 5m,"Bench Press (Barbell)",2,62.5,6,0,0,,,\r
        2020-12-30 18:51:52,"Evening Workout",1h 5m,"Plank",1,0,0,0,45,,,\r
        2020-12-30 18:51:52,"Evening Workout",1h 5m,"Running",1,0,0,5000,0,,,\r
        2021-01-02 09:00:00,"Legs",45m,"Squat (Barbell)",1,100,5,0,0,,,
        """
        let workouts = try HistoryCSV.parse(csv, unit: .kilograms, timeZone: utc)
        #expect(workouts.count == 2)
        let first = workouts[0]
        #expect(first.title == "Evening Workout")
        #expect(first.endedAt.timeIntervalSince(first.startedAt) == 3900)
        #expect(first.exercises.map(\.name) == ["Bench Press (Barbell)", "Plank"], "the cardio row is skipped")
        #expect(first.exercises[0].sets == [.reps(count: 8, weight: .kilograms(60)), .reps(count: 6, weight: .kilograms(62.5))])
        #expect(first.exercises[1].sets == [.duration(seconds: 45)])
    }

    @Test func plainStrongWeightsUseTheUsersUnitAndSemicolonsWork() throws {
        let csv = """
        Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds
        2024-11-28 17:36:08;B;35m;Bent Over Row (Barbell);1;100;5;0;0
        """
        let workouts = try HistoryCSV.parse(csv, unit: .pounds, timeZone: utc)
        #expect(workouts[0].exercises[0].sets == [.reps(count: 5, weight: Mass(100, unit: .pounds))])
    }

    @Test func readsAHevyExport() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Chest, finally","30 Jun 2025, 19:56","30 Jun 2025, 20:58","","Incline Bench Press (Dumbbell)",,"",0,"warmup",20,12,,,
        "Chest, finally","30 Jun 2025, 19:56","30 Jun 2025, 20:58","","Incline Bench Press (Dumbbell)",,"",1,"normal",30,10,,,
        "Chest, finally","30 Jun 2025, 19:56","30 Jun 2025, 20:58","","Plank",,"",0,"normal",,,,60,
        """
        let workouts = try HistoryCSV.parse(csv, unit: .pounds, timeZone: utc)
        #expect(workouts.count == 1)
        #expect(workouts[0].title == "Chest, finally")
        #expect(workouts[0].startedAt == date("2025-06-30 19:56"))
        #expect(workouts[0].endedAt == date("2025-06-30 20:58"))
        #expect(workouts[0].exercises[0].sets == [.reps(count: 12, weight: .kilograms(20)), .reps(count: 10, weight: .kilograms(30))])
        #expect(workouts[0].exercises[1].sets == [.duration(seconds: 60)])
    }

    @Test func unknownFilesAreRefused() {
        #expect(throws: HistoryCSV.ParseError.unrecognized) { try HistoryCSV.parse("a,b,c\n1,2,3", unit: .kilograms, timeZone: utc) }
        let empty = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds\n"
        #expect(throws: HistoryCSV.ParseError.noWorkouts) { try HistoryCSV.parse(empty, unit: .kilograms, timeZone: utc) }
    }

    @Test func durationsAreRead() {
        #expect(HistoryCSV.seconds(of: "2h 38m") == 9480)
        #expect(HistoryCSV.seconds(of: "45m") == 2700)
        #expect(HistoryCSV.seconds(of: "") == 0)
    }
}

struct ImportedExerciseNamesTests {
    private let english: [String: String] = [
        "barbell-bench-press": "Bench Press",
        "dumbbell-bench-press": "Dumbbell Bench Press",
        "incline-barbell-bench-press": "Incline Bench Press",
        "barbell-back-squat": "Back Squat",
        "pull-up": "Pull-Up",
        "plank": "Plank",
        "lat-pulldown": "Lat Pulldown",
    ]

    private func key(_ name: String, _ kind: TrackingKind = .reps) -> String? {
        ImportedExerciseNames.builtInKey(for: name, kind: kind) { english[$0] ?? $0 }
    }

    @Test func matchesCommonStrongAndHevyNames() {
        #expect(key("Bench Press (Barbell)") == "barbell-bench-press")
        #expect(key("Bench Press (Dumbbell)") == "dumbbell-bench-press")
        #expect(key("Squat (Barbell)") == "barbell-back-squat")
        #expect(key("Pull Up") == "pull-up")
        #expect(key("Lat Pulldown (Cable)") == "lat-pulldown")
        #expect(key("Plank", .duration) == "plank")
    }

    @Test func doesNotGuessAcrossEquipmentOrKind() {
        #expect(key("Incline Bench Press (Dumbbell)") == nil, "the barbell version isn't a match")
        #expect(key("Plank") == nil, "a reps plank isn't the timed one")
        #expect(key("Zercher Squat (Barbell)") == nil)
    }

    @Test func everyAliasPointsAtABuiltIn() {
        for key in ImportedExerciseNames.aliases.values {
            #expect(ExerciseCatalog.exercise(forKey: key) != nil, "\(key)")
        }
    }
}
