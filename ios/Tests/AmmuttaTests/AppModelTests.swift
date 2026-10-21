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

    @Test func planLinksResolveNamesAndSaveOnlyOnConfirm() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        model.load()
        // English names match built-ins in any app language; unknown names become custom exercises.
        let link = "ammutta://plan?v=1&name=Link%20Day&e=Bench%20Press:3x5@80:180&e=Band%20Pull-Apart:3x15&e=plank:2x45s:60"
        guard case .success(let preview) = model.preparePlanImport(from: link) else {
            Issue.record("Link did not parse")
            return
        }
        #expect(preview.plan.name == "Link Day")
        #expect(preview.plan.exercises.map(\.exercise).first == .builtIn(key: "barbell-bench-press"))
        #expect(preview.newExercises.map(\.name) == ["Band Pull-Apart"])
        #expect(preview.plan.exercises[1].restSeconds == model.defaultRestSeconds)
        #expect(model.plans.isEmpty)
        #expect(model.customExercises.isEmpty)

        model.confirmImport(preview)
        #expect(model.plans.count == 1)
        #expect(model.customExercises.map(\.name) == ["Band Pull-Apart"])
        #expect(model.selectedTab == .plans)

        // A second import reuses the custom exercise instead of duplicating it.
        guard case .success(let again) = model.preparePlanImport(from: link) else {
            Issue.record("Link did not parse")
            return
        }
        #expect(again.newExercises.isEmpty)
    }

    @Test func sharedLinksImportBackToTheSamePlan() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        let plan = legDay()
        let url = try #require(model.shareURL(for: plan))
        guard case .success(let preview) = model.preparePlanImport(from: url.absoluteString) else {
            Issue.record("Shared link did not parse")
            return
        }
        #expect(preview.plan.exercises.map(\.exercise) == plan.exercises.map(\.exercise))
        #expect(preview.plan.exercises.map(\.sets) == plan.exercises.map(\.sets))
    }

    @Test func badLinksReportAnError() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        guard case .failure(let error) = model.preparePlanImport(from: "ammutta://plan?v=1&name=X&e=plank:10") else {
            Issue.record("Bad link was accepted")
            return
        }
        #expect(error == .invalidExercise(1))
        #expect(!L10n.importError(error).isEmpty)
    }

    @Test func customNamesCannotDuplicateBuiltInsOfTheSameKind() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        let plank = ExerciseText.name("plank")
        #expect(model.isDuplicateName(plank.uppercased(), kind: .duration, excluding: nil))
        #expect(!model.isDuplicateName(plank, kind: .reps, excluding: nil))
    }
}
