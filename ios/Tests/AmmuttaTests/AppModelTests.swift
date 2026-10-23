import AmmuttaCore
import AmmuttaPersistence
import Foundation
import Testing
@testable import Ammutta

/// Records what would be scheduled with the system.
@MainActor
final class RecordingAlerting: TimerAlerting {
    var status: AlertAuthorization = .allowed
    private(set) var current: [String: TimerAlertRequest] = [:]
    private(set) var permissionRequests = 0

    func authorization() async -> AlertAuthorization { status == .notDetermined ? .notDetermined : status }
    func requestAuthorization() async -> AlertAuthorization {
        permissionRequests += 1
        status = .allowed
        return status
    }
    func replace(id: String, with alert: TimerAlertRequest?) async { current[id] = alert }
}

@MainActor
struct TimerAlertTests {
    private func plan() -> Plan {
        Plan(name: "Legs", exercises: [
            PlanExercise(exercise: .builtIn(key: "barbell-back-squat"), kind: .reps, restSeconds: 120,
                         sets: [.reps(count: 5, weight: .kilograms(100)), .reps(count: 5, weight: .kilograms(100))]),
            PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60, sets: [.duration(seconds: 45)]),
        ], createdAt: .now)
    }

    private func makeModel(_ alerts: RecordingAlerting) throws -> AppModel {
        let defaults = try #require(UserDefaults(suiteName: "ammutta.tests.\(UUID().uuidString)"))
        return AppModel(store: try AmmuttaStore(inMemory: true), defaults: defaults, alerts: alerts)
    }

    @Test func restSchedulesALockScreenAlertAndSkippingRemovesIt() async throws {
        let alerts = RecordingAlerting()
        alerts.status = .notDetermined
        let model = try makeModel(alerts)
        model.startWorkout(from: plan())
        let session = try #require(model.session)
        await session.alertsSettled()
        #expect(alerts.current.isEmpty)
        #expect(alerts.permissionRequests == 0)

        session.send(.logSet(try #require(session.workout.nextPendingSetID)))
        await session.alertsSettled()
        let alert = try #require(alerts.current.values.first)
        #expect(alert.fireDate == session.workout.timer?.endsAt)
        #expect(alert.title == L10n.alertRestTitle)
        #expect(alert.body.contains(ExerciseText.name("barbell-back-squat")))
        #expect(alerts.permissionRequests == 1)
        #expect(!session.alertsOff)

        session.send(.adjustRest(seconds: 15))
        await session.alertsSettled()
        #expect(alerts.current.values.first?.fireDate == session.workout.timer?.endsAt)

        session.send(.skipRest)
        await session.alertsSettled()
        #expect(alerts.current.isEmpty)
    }

    @Test func timedSetsAlertAndDiscardingCancels() async throws {
        let alerts = RecordingAlerting()
        let model = try makeModel(alerts)
        model.startWorkout(from: plan())
        let session = try #require(model.session)
        let plank = session.workout.exercises[1].sets[0].id
        session.send(.startWork(plank))
        await session.alertsSettled()
        #expect(alerts.current.values.first?.title == L10n.alertWorkTitle)

        model.discardActiveWorkout()
        await session.alertsSettled()
        #expect(alerts.current.isEmpty)
    }

    @Test func declinedNotificationsShowTheAlertsOffLine() async throws {
        let alerts = RecordingAlerting()
        alerts.status = .denied
        let model = try makeModel(alerts)
        model.startWorkout(from: plan())
        let session = try #require(model.session)
        session.send(.logSet(try #require(session.workout.nextPendingSetID)))
        await session.alertsSettled()
        #expect(session.alertsOff)
    }
}

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

    /// Every built-in exercise has a name, a technique tip and muscles worked in the catalog.
    @Test func everyBuiltInHasANameTipAndMuscles() {
        for exercise in ExerciseCatalog.all {
            #expect(ExerciseText.name(exercise.key) != "exercise." + exercise.key, "\(exercise.key) has no name")
            #expect(ExerciseText.tip(exercise.key) != "tip." + exercise.key, "\(exercise.key) has no tip")
            #expect(ExerciseText.muscles(exercise.key) != "muscles." + exercise.key, "\(exercise.key) has no muscles")
        }
    }

    @Test func searchFindsExercisesByMuscle() throws {
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults())
        let glutes = model.entries(model.builtInEntries, matching: ExerciseText.muscle(.glutes)).map(\.ref)
        #expect(glutes.contains(.builtIn(key: "barbell-hip-thrust")))
        #expect(!glutes.contains(.builtIn(key: "barbell-curl")))
        let hamstrings = ExerciseText.muscles("leg-curl")
        #expect(model.entries(model.builtInEntries, matching: hamstrings).map(\.ref).contains(.builtIn(key: "lying-leg-curl")))
    }

    @Test func heartRateReadingsAreStoredWithTheWorkout() throws {
        let sensor = FakeHeartRateSource(sensorName: "Strap")
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults(), heartRate: sensor)
        model.load()
        let plan = legDay()
        model.save(plan)
        #expect(!sensor.workoutActive)

        model.startWorkout(from: plan)
        #expect(sensor.workoutActive)
        let session = try #require(model.session)
        let start = session.workout.startedAt
        sensor.emit(120, at: start.addingTimeInterval(10))
        sensor.emit(200, at: start.addingTimeInterval(12)) // too soon after the last one
        sensor.emit(150, at: start.addingTimeInterval(20))
        #expect(session.workout.heartRate.map(\.bpm) == [120, 150])

        session.send(.finish)
        sensor.emit(170, at: start.addingTimeInterval(40)) // after the end
        model.closeFinishedSession()
        #expect(!sensor.workoutActive)
        let saved = try #require(model.history.first)
        #expect(saved.heartRate.map(\.bpm) == [120, 150])
        #expect(WorkoutSummary(saved).averageHeartRate == 135)
        #expect(WorkoutSummary(saved).maxHeartRate == 150)
    }

    @Test func discardingAWorkoutReleasesTheSensor() throws {
        let sensor = FakeHeartRateSource(sensorName: "Strap")
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults(), heartRate: sensor)
        model.startWorkout(from: legDay())
        #expect(sensor.workoutActive)
        model.discardActiveWorkout()
        #expect(!sensor.workoutActive)
    }

    private func finishWorkout(in model: AppModel) throws -> WorkoutID {
        model.startWorkout(from: legDay())
        let session = try #require(model.session)
        session.send(.finish)
        model.closeFinishedSession()
        return session.workout.id
    }

    @Test func finishedAndDeletedWorkoutsSyncToHealthWhenOn() async throws {
        let health = FakeHealthSync()
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults(), healthService: health)
        model.load()
        model.health.isEnabled = true
        await model.health.authorizeAndRun()
        #expect(model.health.isAuthorized)

        let id = try finishWorkout(in: model)
        await model.health.settled()
        #expect(health.saved == [id])
        #expect(model.health.queue.jobs.isEmpty)

        model.deleteWorkout(id)
        await model.health.settled()
        #expect(health.saved.isEmpty)
        #expect(health.deleted == [id])
    }

    @Test func healthSyncIsOffByDefault() async throws {
        let health = FakeHealthSync()
        let model = AppModel(store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults(), healthService: health)
        _ = try finishWorkout(in: model)
        await model.health.settled()
        #expect(!model.health.isEnabled)
        #expect(health.saved.isEmpty)
        #expect(model.health.queue.jobs.isEmpty)
    }

    @Test func failedHealthWritesStayQueuedAndRetry() async throws {
        let health = FakeHealthSync()
        health.isAuthorized = true
        health.failing = true
        let defaults = try makeDefaults()
        let store = try AmmuttaStore(inMemory: true)
        let model = AppModel(store: store, defaults: defaults, healthService: health)
        model.health.isEnabled = true
        await model.health.settled()

        let id = try finishWorkout(in: model)
        await model.health.settled()
        #expect(health.saved.isEmpty)
        #expect(model.health.queue.jobs == [.save(id)])

        // The queue survives a relaunch and runs once Health works again.
        health.failing = false
        let relaunched = AppModel(store: store, defaults: defaults, healthService: health)
        #expect(relaunched.health.queue.jobs == [.save(id)])
        relaunched.load()
        await relaunched.health.settled()
        #expect(health.saved == [id])
        #expect(relaunched.health.queue.jobs.isEmpty)
    }

    private func agentModel(
        _ server: FakeAgentServer, store: FakeAgentStore = FakeAgentStore(), accounts: MemoryAgentAccountStore = MemoryAgentAccountStore()
    ) throws -> AppModel {
        let model = AppModel(
            store: try AmmuttaStore(inMemory: true), defaults: try makeDefaults(),
            agentServer: server, agentStore: store, agentAccounts: accounts
        )
        model.load()
        return model
    }

    @Test func connectingAgentsSendsTheDataAndEveryChange() async throws {
        let server = FakeAgentServer()
        let accounts = MemoryAgentAccountStore()
        let model = try agentModel(server, accounts: accounts)
        #expect(model.agents.isAvailable && !model.agents.isEnabled)
        model.save(legDay())
        await model.agents.settled()
        #expect(server.snapshots.isEmpty, "nothing leaves the phone while off")

        model.agents.activate()
        await model.agents.settled()
        #expect(accounts.account != nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(AgentSnapshot.self, from: try #require(server.snapshots.last))
        #expect(first.plans.map(\.name) == ["Legs"])

        model.save(Plan(name: "Arms", exercises: [.make(exercise: .builtIn(key: "dumbbell-curl"), kind: .reps, restSeconds: 60)], createdAt: .now))
        await model.agents.settled()
        let second = try decoder.decode(AgentSnapshot.self, from: try #require(server.snapshots.last))
        #expect(Set(second.plans.map(\.name)) == ["Legs", "Arms"])

        await model.agents.startPairing()
        #expect(model.agents.pairing?.code == "K7M2QX9P")
    }

    @Test func plansWrittenByAgentsAreImportedAndUpdatesKeepThePlan() async throws {
        let server = FakeAgentServer()
        let model = try agentModel(server)
        let legs = legDay()
        model.save(legs)
        server.pending = [
            AgentInboxItem(id: "1", planId: nil, name: "Pull Day",
                           link: "ammutta://plan?v=1&name=Pull%20Day&e=Band%20Pull-Apart%3A3x15%3A60&e=plank%3A2x45s"),
            AgentInboxItem(id: "2", planId: legs.id.rawValue.uuidString, name: "Legs v2",
                           link: "ammutta://plan?v=1&name=Legs%20v2&e=barbell-back-squat%3A5x5%40100%3A180"),
            AgentInboxItem(id: "3", planId: nil, name: "Broken", link: "ammutta://plan?v=1&name=Broken"),
        ]
        model.agents.activate()
        await model.agents.settled()

        #expect(server.pending.isEmpty, "imported and unusable items both leave the inbox")
        #expect(Set(model.plans.map(\.name)) == ["Pull Day", "Legs v2"])
        let updated = try #require(model.plan(legs.id))
        #expect(updated.name == "Legs v2")
        #expect(updated.exercises.first?.sets.count == 5)
        #expect(model.customExercises.map(\.name) == ["Band Pull-Apart"])
    }

    @Test func turningAgentsOffDeletesTheAccount() async throws {
        let server = FakeAgentServer()
        let accounts = MemoryAgentAccountStore()
        let model = try agentModel(server, accounts: accounts)
        model.agents.activate()
        await model.agents.settled()
        let id = try #require(accounts.account?.id)

        model.agents.turnOffAndDeleteData()
        await model.agents.settled()
        #expect(accounts.account == nil)
        #expect(server.deletedAccounts == [id])
    }

    @Test func anUnreachableConnectorKeepsPlansForLater() async throws {
        let server = FakeAgentServer()
        server.failing = true
        server.pending = [AgentInboxItem(id: "1", planId: nil, name: "Later", link: "ammutta://plan?v=1&name=Later&e=plank%3A45s")]
        let model = try agentModel(server)
        model.agents.activate()
        await model.agents.settled()
        #expect(model.agents.isOffline)
        #expect(model.plans.isEmpty)

        server.failing = false
        model.agents.refresh()
        await model.agents.settled()
        #expect(!model.agents.isOffline)
        #expect(model.plans.map(\.name) == ["Later"])
    }

    @Test func withoutASubscriptionNothingIsSent() async throws {
        let server = FakeAgentServer()
        server.active = false
        let appStore = FakeAgentStore()
        let model = try agentModel(server, store: appStore)
        model.save(legDay())
        model.agents.activate()
        await model.agents.settled()
        #expect(!model.agents.isSubscribed)
        #expect(server.snapshots.isEmpty)

        model.save(Plan(name: "Arms", exercises: [.make(exercise: .builtIn(key: "dumbbell-curl"), kind: .reps, restSeconds: 60)], createdAt: .now))
        await model.agents.settled()
        #expect(server.snapshots.isEmpty, "changes aren't sent either")

        // A purchase, renewal or redeemed offer code arrives from the App Store.
        appStore.deliver("signed-transaction")
        await model.agents.settled()
        #expect(server.uploadedTransactions == ["signed-transaction"])
        #expect(model.agents.isSubscribed)
        #expect(server.snapshots.count == 1)
    }

    /// The add-on was on, but the account is gone (a new phone without iCloud Keychain).
    @Test func openingTheScreenMakesAMissingAccount() async throws {
        let server = FakeAgentServer()
        let accounts = MemoryAgentAccountStore()
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "agentsEnabled")
        let model = AppModel(
            store: try AmmuttaStore(inMemory: true), defaults: defaults,
            agentServer: server, agentStore: FakeAgentStore(), agentAccounts: accounts
        )
        model.load()
        #expect(model.agents.isEnabled && accounts.account == nil)

        model.agents.activate()
        await model.agents.settled()
        #expect(accounts.account != nil)
        #expect(model.agents.isSubscribed)
    }

    @Test func refreshSendsTheCurrentAppStoreTransaction() async throws {
        let server = FakeAgentServer()
        let appStore = FakeAgentStore()
        appStore.transaction = "current-transaction"
        let model = try agentModel(server, store: appStore)
        model.agents.activate()
        await model.agents.settled()
        #expect(server.uploadedTransactions == ["current-transaction"])
        #expect(model.agents.isSubscribed)
        #expect(model.agents.accountToken != nil)
    }

    /// The connect sheet's flow: a code, waiting, then the agent that signed in, now in the list.
    @Test func pairingWaitsForTheAgentThenListsIt() async throws {
        let server = FakeAgentServer()
        let model = try agentModel(server)
        model.agents.activate()
        await model.agents.settled()
        #expect(model.agents.connectedAgents.isEmpty)

        await model.agents.startPairing()
        #expect(model.agents.pairingStatus == .waiting)
        await model.agents.watchPairing()
        #expect(model.agents.pairingStatus == .connected(agent: "Claude"))
        #expect(model.agents.connectedAgents.map(\.name) == ["Claude"])

        model.agents.disconnectAgents()
        await model.agents.settled()
        #expect(model.agents.connectedAgents.isEmpty)
        #expect(server.disconnects == 1)
    }

    @Test func closingTheSheetStopsWatching() async throws {
        let server = FakeAgentServer()
        server.agentSigningIn = nil
        let model = try agentModel(server)
        model.agents.activate()
        await model.agents.settled()
        await model.agents.startPairing()
        let watching = Task { await model.agents.watchPairing() }
        try await Task.sleep(for: .milliseconds(100))
        watching.cancel()
        await watching.value
        #expect(model.agents.pairingStatus == .waiting, "closing the sheet stops watching")
    }

    @Test func turningOffClearsTheAgentScreen() async throws {
        let server = FakeAgentServer()
        server.connected = [ConnectedAgent(name: "Claude", connectedAt: .now)]
        let model = try agentModel(server)
        model.agents.activate()
        await model.agents.settled()
        #expect(model.agents.isSubscribed)
        #expect(model.agents.connectedAgents.count == 1)
        #expect(model.agents.lastSynced != nil)

        model.agents.turnOffAndDeleteData()
        await model.agents.settled()
        #expect(!model.agents.isEnabled)
        #expect(!model.agents.isSubscribed)
        #expect(model.agents.connectedAgents.isEmpty)
    }
}
