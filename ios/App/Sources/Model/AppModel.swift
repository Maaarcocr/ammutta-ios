import AmmuttaCore
import AmmuttaPersistence
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "dev.ammutta.app", category: "AppModel")

/// An exercise as shown in lists and pickers, with its name already localized.
struct ExerciseEntry: Identifiable, Hashable {
    let ref: ExerciseRef
    let kind: TrackingKind
    let name: String
    let detail: String
    /// Extra words search matches besides the name: muscles worked and muscle group for built-ins.
    var keywords = ""

    var id: ExerciseRef { ref }

    init(ref: ExerciseRef, kind: TrackingKind, name: String, detail: String) {
        self.ref = ref
        self.kind = kind
        self.name = name
        self.detail = detail
    }

    init(builtIn exercise: BuiltInExercise) {
        self.init(ref: exercise.ref, kind: exercise.kind, name: ExerciseText.name(exercise.key), detail: ExerciseText.equipment(exercise.equipment))
        keywords = ExerciseText.muscles(exercise.key) + " " + ExerciseText.muscle(exercise.muscle)
    }

    var isCustom: Bool {
        if case .custom = ref { return true }
        return false
    }

    /// Stable, language-independent identifier for UI tests.
    var testIdentifier: String {
        switch ref {
        case .builtIn(let key): key
        case .custom(let id): id.rawValue.uuidString
        }
    }
}

struct MonthGroup: Identifiable {
    let month: Date
    let workouts: [Workout]
    var id: Date { month }
}

/// App-wide state: loads data from the store, keeps it in memory for the screens and
/// writes every change straight back. Screens never touch SwiftData directly.
@Observable
final class AppModel {
    @ObservationIgnored private let store: AmmuttaStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let alerts: any TimerAlerting
    @ObservationIgnored private let activityPresenter: any WorkoutActivityPresenting

    private(set) var plans: [Plan] = []
    private(set) var customExercises: [CustomExercise] = []
    /// Completed workouts, newest first.
    private(set) var history: [Workout] = []
    /// The active workout, shown full screen above the tabs while it exists.
    var session: WorkoutSession?
    var showingError = false
    var selectedTab: AppTab = .plans
    /// A plan link being previewed (opened from a link, or pasted).
    var importRequest: ImportRequest?
    /// A link opened during a workout, shown when the workout screen closes.
    var deferredImport: ImportRequest?

    private var storedWeightUnit: WeightUnit
    private var storedDefaultRest: Int

    private enum Keys {
        static let weightUnit = "weightUnit"
        static let defaultRest = "defaultRestSeconds"
    }

    init(
        store: AmmuttaStore,
        defaults: UserDefaults = .standard,
        alerts: any TimerAlerting = DisabledAlerting(),
        activityPresenter: any WorkoutActivityPresenting = DisabledActivityPresenter()
    ) {
        self.store = store
        self.defaults = defaults
        self.alerts = alerts
        self.activityPresenter = activityPresenter
        let localeDefault: WeightUnit = Locale.current.measurementSystem == .us ? .pounds : .kilograms
        storedWeightUnit = defaults.string(forKey: Keys.weightUnit).flatMap(WeightUnit.init(rawValue:)) ?? localeDefault
        if defaults.object(forKey: Keys.defaultRest) != nil {
            let saved = defaults.integer(forKey: Keys.defaultRest)
            storedDefaultRest = min(max(saved, Limits.restSeconds.lowerBound), Limits.restSeconds.upperBound)
        } else {
            storedDefaultRest = 150
        }
    }

    // MARK: Settings

    var weightUnit: WeightUnit {
        get { storedWeightUnit }
        set {
            storedWeightUnit = newValue
            defaults.set(newValue.rawValue, forKey: Keys.weightUnit)
        }
    }

    var defaultRestSeconds: Int {
        get { storedDefaultRest }
        set {
            storedDefaultRest = newValue
            defaults.set(newValue, forKey: Keys.defaultRest)
        }
    }

    // MARK: Loading

    func load() {
        do {
            customExercises = try store.customExercises()
            plans = try sortedPlans()
            history = try store.completedWorkouts()
            if let active = try store.activeWorkout() {
                session = makeSession(active)
            }
        } catch {
            report(error)
        }
    }

    private func sortedPlans() throws -> [Plan] {
        try store.plans().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func report(_ error: any Error) {
        logger.error("Store operation failed: \(String(describing: error), privacy: .private)")
        showingError = true
    }

    // MARK: Exercises

    func name(of ref: ExerciseRef, snapshot: String? = nil) -> String {
        switch ref {
        case .builtIn(let key):
            return ExerciseText.name(key)
        case .custom(let id):
            return customExercises.first { $0.id == id }?.name ?? snapshot ?? L10n.exerciseDeleted
        }
    }

    var customEntries: [ExerciseEntry] {
        customExercises
            .map { ExerciseEntry(ref: $0.ref, kind: $0.kind, name: $0.name, detail: L10n.customLabel) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var builtInEntries: [ExerciseEntry] {
        ExerciseCatalog.all
            .map(ExerciseEntry.init(builtIn:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Accent- and case-insensitive search in the current language, by name or muscle.
    func entries(_ entries: [ExerciseEntry], matching query: String) -> [ExerciseEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.name.localizedStandardContains(trimmed) || $0.keywords.localizedStandardContains(trimmed) }
    }

    func entry(for ref: ExerciseRef) -> ExerciseEntry? {
        switch ref {
        case .builtIn(let key):
            guard let builtIn = ExerciseCatalog.exercise(forKey: key) else { return nil }
            return ExerciseEntry(builtIn: builtIn)
        case .custom(let id):
            guard let custom = customExercises.first(where: { $0.id == id }) else { return nil }
            return ExerciseEntry(ref: ref, kind: custom.kind, name: custom.name, detail: L10n.customLabel)
        }
    }

    func customExercise(_ id: ExerciseID) -> CustomExercise? {
        customExercises.first { $0.id == id }
    }

    /// Names are unique per tracking kind across custom and built-in exercises in the current language.
    func isDuplicateName(_ name: String, kind: TrackingKind, excluding: ExerciseID?) -> Bool {
        let custom = customExercises.filter { $0.kind == kind && $0.id != excluding }.map(\.name)
        let builtIn = ExerciseCatalog.all.filter { $0.kind == kind }.map { ExerciseText.name($0.key) }
        return ExerciseNames.isDuplicate(name, among: custom + builtIn)
    }

    /// Used exercises can be renamed but not deleted or change kind, so history keeps its meaning.
    func isUsed(_ ref: ExerciseRef) -> Bool {
        plans.contains { $0.exercises.contains { $0.exercise == ref } }
            || history.contains { $0.exercises.contains { $0.exercise == ref } }
            || (session?.workout.exercises.contains { $0.exercise == ref } ?? false)
    }

    func save(_ exercise: CustomExercise) {
        do {
            try store.save(exercise)
            customExercises = try store.customExercises()
        } catch {
            report(error)
        }
    }

    func delete(_ exercise: CustomExercise) {
        guard !isUsed(exercise.ref) else { return }
        do {
            try store.deleteCustomExercise(exercise.id)
            customExercises = try store.customExercises()
        } catch {
            report(error)
        }
    }

    // MARK: Plans

    func plan(_ id: PlanID) -> Plan? { plans.first { $0.id == id } }

    func save(_ plan: Plan) {
        do {
            try store.save(plan)
            plans = try sortedPlans()
        } catch {
            report(error)
        }
    }

    func delete(_ plan: Plan) {
        do {
            try store.deletePlan(plan.id)
            plans = try sortedPlans()
        } catch {
            report(error)
        }
    }

    func duplicate(_ plan: Plan) {
        save(plan.duplicated(name: L10n.copyName(plan.name), now: .now))
    }

    func lastPerformed(_ plan: Plan) -> Date? {
        history.first { $0.planID == plan.id }?.startedAt
    }

    // MARK: Workouts

    func startWorkout(from plan: Plan) {
        guard session == nil else { return }
        let names = Dictionary(customExercises.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let workout = Workout.start(from: plan, now: .now, customNames: names)
        do {
            try store.save(workout)
            session = makeSession(workout)
        } catch {
            report(error)
        }
    }

    func discardActiveWorkout() {
        guard let session else { return }
        session.close()
        do {
            try store.deleteWorkout(session.workout.id)
        } catch {
            report(error)
        }
        self.session = nil
    }

    /// Called from the summary screen once the user is done looking at a finished workout.
    func closeFinishedSession() {
        session = nil
        reloadHistory()
    }

    func workout(_ id: WorkoutID) -> Workout? { history.first { $0.id == id } }

    func deleteWorkout(_ id: WorkoutID) {
        do {
            try store.deleteWorkout(id)
        } catch {
            report(error)
        }
        reloadHistory()
    }

    func lastPerformance(of ref: ExerciseRef) -> ExerciseSession? {
        ExerciseProgress.lastPerformance(of: ref, in: history)
    }

    func sessions(of ref: ExerciseRef) -> [ExerciseSession] {
        ExerciseProgress.sessions(of: ref, in: history)
    }

    var historyByMonth: [MonthGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: history) { workout in
            calendar.dateInterval(of: .month, for: workout.startedAt)?.start ?? workout.startedAt
        }
        return groups
            .map { MonthGroup(month: $0.key, workouts: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.month > $1.month }
    }

    private func reloadHistory() {
        do {
            history = try store.completedWorkouts()
        } catch {
            report(error)
        }
    }

    private func makeSession(_ workout: Workout) -> WorkoutSession {
        WorkoutSession(
            workout: workout,
            alerts: alerts,
            alertContent: { [weak self] plan, workout in
                self?.alertContent(plan, in: workout) ?? TimerAlertRequest(fireDate: plan.fireDate, title: "", body: "")
            },
            activity: activityPresenter,
            activityContent: { [weak self] workout in
                self?.activityContent(for: workout)
                    ?? (WorkoutActivityAttributes(planName: workout.planName, startedAt: workout.startedAt),
                        WorkoutActivityAttributes.ContentState(exercise: workout.planName, detail: ""))
            },
            persist: { [weak self] updated in
                self?.persist(updated)
            }
        )
    }

    /// What the Live Activity shows: the exercise to do now or next, its set, and any countdown.
    func activityContent(for workout: Workout) -> (WorkoutActivityAttributes, WorkoutActivityAttributes.ContentState) {
        let attributes = WorkoutActivityAttributes(planName: workout.planName, startedAt: workout.startedAt)
        var state = WorkoutActivityAttributes.ContentState(exercise: workout.planName, detail: L10n.activityAllDone)
        let focusSet = workout.timer?.workSetID ?? workout.nextPendingSetID
        if let focusSet, let location = workout.location(ofSet: focusSet) {
            let exercise = workout.exercises[location.exercise]
            state.exercise = name(of: exercise.exercise, snapshot: exercise.nameSnapshot)
            state.detail = L10n.activitySetOf(location.set + 1, exercise.sets.count)
        }
        if let timer = workout.timer {
            state.timerLabel = timer.isRest ? L10n.timerRestText : L10n.timerWorkText
            state.timerStart = timer.startedAt
            state.timerEnd = timer.endsAt
        }
        return (attributes, state)
    }

    /// The localized text of a Lock Screen timer alert.
    func alertContent(_ plan: TimerAlertPlan, in workout: Workout) -> TimerAlertRequest {
        switch plan.kind {
        case .restOver(let nextSet):
            var body = L10n.alertRestBody
            if let nextSet, let location = workout.location(ofSet: nextSet) {
                let exercise = workout.exercises[location.exercise]
                body = L10n.alertNextSet(name(of: exercise.exercise, snapshot: exercise.nameSnapshot), location.set + 1)
            }
            return TimerAlertRequest(fireDate: plan.fireDate, title: L10n.alertRestTitle, body: body)
        case .workDone(let set):
            var name = ""
            if let location = workout.location(ofSet: set) {
                let exercise = workout.exercises[location.exercise]
                name = self.name(of: exercise.exercise, snapshot: exercise.nameSnapshot)
            }
            return TimerAlertRequest(fireDate: plan.fireDate, title: L10n.alertWorkTitle, body: L10n.alertWorkBody(name))
        }
    }

    private func persist(_ workout: Workout) {
        do {
            try store.save(workout)
        } catch {
            report(error)
        }
    }

    // MARK: UI testing

    /// A ready-made plan so UI tests can go straight to a workout.
    func seedSamplePlan() {
        let plan = Plan(
            name: "Push Day",
            exercises: [
                PlanExercise(exercise: .builtIn(key: "barbell-bench-press"), kind: .reps, restSeconds: 90,
                             sets: Array(repeating: .reps(count: 8, weight: .kilograms(60)), count: 3)),
                PlanExercise(exercise: .builtIn(key: "plank"), kind: .duration, restSeconds: 60,
                             sets: Array(repeating: .duration(seconds: 30), count: 2)),
            ],
            createdAt: .now
        )
        save(plan)
    }
}
