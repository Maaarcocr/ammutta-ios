import AmmuttaCore
import AmmuttaPersistence
import Foundation
import Testing
@testable import Ammutta

@MainActor
struct AppModelTests {
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ammutta.tests.\(UUID().uuidString)"))
    }

    private func legDay() -> Plan {
        Plan(name: "Legs", exercises: [.make(exercise: .builtIn(key: "barbell-back-squat"), kind: .reps, restSeconds: 120)], createdAt: .now)
    }

    @Test func fullWorkoutFlowEndsInHistory() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        model.load()
        let plan = legDay()
        model.save(plan)
        #expect(model.plans == [plan])

        model.startWorkout(from: plan)
        let session = try #require(model.session)
        let first = try #require(session.workout.nextPendingSetID)
        session.send(.logSet(first))
        #expect(session.workout.timer?.isRest == true)

        session.send(.finish)
        #expect(session.isFinished)
        model.closeFinishedSession()
        #expect(model.session == nil)
        #expect(model.history.count == 1)
        #expect(model.lastPerformed(plan) != nil)
        #expect(model.isUsed(.builtIn(key: "barbell-back-squat")))
        #expect(model.lastPerformance(of: .builtIn(key: "barbell-back-squat"))?.results.count == 1)
    }

    @Test func activeWorkoutIsRestoredOnRelaunch() throws {
        let store = try AmmuttaStore(inMemory: true)
        let defaults = try makeDefaults()
        let model = AppModel(store: store, defaults: defaults)
        let plan = legDay()
        model.save(plan)
        model.startWorkout(from: plan)
        let original = try #require(model.session?.workout.id)

        let relaunched = AppModel(store: store, defaults: defaults)
        relaunched.load()
        #expect(relaunched.session?.workout.id == original)
    }

    @Test func discardingRemovesTheActiveWorkout() throws {
        let store = try AmmuttaStore(inMemory: true)
        let model = AppModel(store: store, defaults: try makeDefaults())
        model.startWorkout(from: legDay())
        model.discardActiveWorkout()
        #expect(model.session == nil)
        #expect(try store.activeWorkout() == nil)
        #expect(model.history.isEmpty)
    }

    @Test func settingsPersist() throws {
        let store = try AmmuttaStore(inMemory: true)
        let defaults = try makeDefaults()
        let model = AppModel(store: store, defaults: defaults)
        model.weightUnit = .pounds
        model.defaultRestSeconds = 90
        let reloaded = AppModel(store: store, defaults: defaults)
        #expect(reloaded.weightUnit == .pounds)
        #expect(reloaded.defaultRestSeconds == 90)
    }

    @Test func customNamesCannotDuplicateBuiltInsOfTheSameKind() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        let plank = ExerciseText.name("plank")
        #expect(model.isDuplicateName(plank.uppercased(), kind: .duration, excluding: nil))
        #expect(!model.isDuplicateName(plank, kind: .reps, excluding: nil))
    }
}
