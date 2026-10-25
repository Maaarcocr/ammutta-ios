import AmmuttaCore
import SwiftUI
import UIKit

/// The active workout: one scrolling dashboard of exercises, with the current one
/// expanded and the rest or exercise countdown pinned to the bottom.
struct WorkoutView: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var model
    @State private var confirmingDiscard = false
    @State private var sheet: WorkoutSheet?
    /// The reps, weight or seconds field being typed into, if any.
    @FocusState private var focusedField: SetField?
    /// Exercises shown expanded: starts as the current one, and resets to it whenever it moves on.
    @State private var expanded: Set<UUID>

    init(session: WorkoutSession) {
        self.session = session
        _expanded = State(initialValue: Self.currentExercise(in: session.workout).map { Set([$0]) } ?? [])
    }

    var body: some View {
        if session.isFinished {
            WorkoutSummaryView(workout: session.workout)
        } else {
            active
        }
    }

    private var currentExerciseID: UUID? { Self.currentExercise(in: session.workout) }

    private static func currentExercise(in workout: Workout) -> UUID? {
        guard let setID = workout.nextPendingSetID, let location = workout.location(ofSet: setID) else { return nil }
        return workout.exercises[location.exercise].id
    }

    private var active: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if session.alertsOff {
                        AlertsOffRow()
                    }
                    if session.workout.exercises.isEmpty {
                        ContentUnavailableView(L10n.workoutNoExercises, systemImage: "dumbbell")
                    }
                    ForEach(session.workout.exercises) { exercise in
                        ExerciseCard(
                            exercise: exercise,
                            session: session,
                            isExpanded: expanded.contains(exercise.id),
                            focus: $focusedField,
                            toggle: { toggle(exercise.id) },
                            replace: { sheet = .replace(exercise: exercise.id) }
                        )
                    }
                    Button {
                        sheet = .addExercise
                    } label: {
                        Label(L10n.planEditorAddExercise, systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("workout.addExercise")
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                if let timer = session.workout.timer {
                    TimerBar(timer: timer, session: session)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if session.workout.exercises.count > 1 {
                            Button {
                                sheet = .reorder
                            } label: {
                                Label(L10n.workoutReorder, systemImage: "arrow.up.arrow.down")
                            }
                            .accessibilityIdentifier("workout.reorder")
                        }
                        Button(role: .destructive) {
                            confirmingDiscard = true
                        } label: {
                            Label(L10n.workoutDiscard, systemImage: "trash")
                        }
                        .accessibilityIdentifier("workout.discard")
                    } label: {
                        Label(L10n.more, systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("workout.more")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(session.workout.planName)
                            .font(.headline)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text(session.workout.startedAt, style: .timer)
                            if model.heartRate.sensorID != nil {
                                HeartRateReading(bpm: model.heartRate.bpm)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.done) { focusedField = nil }
                        .accessibilityIdentifier("keyboard.done")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.workoutFinish) {
                        session.send(.finish)
                    }
                    .accessibilityIdentifier("workout.finish")
                }
            }
            .alert(L10n.workoutDiscardTitle, isPresented: $confirmingDiscard) {
                Button(L10n.workoutDiscard, role: .destructive) {
                    model.discardActiveWorkout()
                }
                .accessibilityIdentifier("workout.confirmDiscard")
                Button(L10n.cancel, role: .cancel) {}
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .addExercise:
                    ExercisePickerView { ref, kind in
                        session.send(.addExercise(model.exerciseToAdd(ref, kind: kind)))
                    }
                case .replace(let exerciseID):
                    ExercisePickerView { ref, kind in
                        session.send(.replaceExercise(exerciseID, with: ref, kind: kind, nameSnapshot: model.nameSnapshot(for: ref)))
                    }
                case .reorder:
                    ReorderExercisesSheet(session: session)
                }
            }
            .sensoryFeedback(.success, trigger: session.timerEndedCount)
            .onChange(of: currentExerciseID) { _, current in
                expanded = current.map { Set([$0]) } ?? []
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// The one sheet the workout screen shows at a time.
private enum WorkoutSheet: Identifiable {
    case addExercise
    case replace(exercise: UUID)
    case reorder

    var id: String {
        switch self {
        case .addExercise: "add"
        case .replace(let exercise): "replace-\(exercise)"
        case .reorder: "reorder"
        }
    }
}

/// Drag handles to change the order of the workout's exercises.
private struct ReorderExercisesSheet: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.workout.exercises) { exercise in
                    HStack {
                        Text(model.name(of: exercise.exercise, snapshot: exercise.nameSnapshot))
                        Spacer()
                        Text(L10n.fraction(exercise.loggedCount, exercise.sets.count))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let id = session.workout.exercises[from].id
                    session.send(.moveExercise(id, to: destination > from ? destination - 1 : destination))
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(L10n.workoutReorder)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { dismiss() }
                        .accessibilityIdentifier("reorder.done")
                }
            }
        }
    }
}

private struct ExerciseCard: View {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let isExpanded: Bool
    let focus: FocusState<SetField?>.Binding
    let toggle: () -> Void
    let replace: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                header
                // Replacing or removing never touches logged sets.
                if exercise.loggedCount == 0 {
                    Menu {
                        Button(action: replace) {
                            Label(L10n.workoutReplaceExercise, systemImage: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityIdentifier("workout.replaceExercise")
                        Button(role: .destructive) {
                            session.send(.removeExercise(exercise.id))
                        } label: {
                            Label(L10n.workoutRemoveExercise, systemImage: "trash")
                        }
                        .accessibilityIdentifier("workout.removeExercise")
                    } label: {
                        Label(L10n.workoutExerciseOptions, systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("workout.exerciseMenu")
                }
            }

            if isExpanded {
                let last = model.lastPerformance(of: exercise.exercise)
                let recordSets = model.records(of: exercise.exercise).recordSets(exercise.sets)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    Divider()
                    SetRow(
                        set: set,
                        number: setIndex + 1,
                        kind: exercise.kind,
                        last: last?.results[safe: setIndex],
                        isRecord: recordSets.contains(set.id),
                        isNext: set.id == session.workout.nextPendingSetID,
                        canRemove: exercise.sets.count > 1,
                        session: session,
                        focus: focus
                    )
                }
                Divider()
                Button {
                    session.send(.addSet(exercise: exercise.id, newSetID: UUID()))
                } label: {
                    Label(L10n.addSet, systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 20))
    }

    /// The name and progress; tapping it expands or collapses the sets.
    private var header: some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name(of: exercise.exercise, snapshot: exercise.nameSnapshot))
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Text(L10n.fraction(exercise.loggedCount, exercise.sets.count))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct SetRow: View {
    let set: WorkoutSet
    let number: Int
    let kind: TrackingKind
    let last: SetValue?
    /// Logging this set beat the exercise's history.
    let isRecord: Bool
    let isNext: Bool
    let canRemove: Bool
    let session: WorkoutSession
    let focus: FocusState<SetField?>.Binding
    @Environment(AppModel.self) private var model
    @State private var editing = false

    private var unit: WeightUnit { model.weightUnit }
    private var isRunning: Bool { session.workout.timer?.workSetID == set.id }
    private var showsControls: Bool { (isNext && !set.status.isLogged) || editing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(number, format: .number)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 24)
                    .foregroundStyle(isNext ? Color.accentColor : Color.secondary)

                Button {
                    editing.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            valueText
                            if isRecord {
                                RecordBadge()
                            }
                        }
                        if set.status.isSkipped {
                            Text(L10n.skipped)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let last {
                            Text(L10n.lastTime(Format.value(last, unit: unit)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                rowMenu
                trailingAction
            }
            if showsControls {
                controls
            }
        }
        .padding(.vertical, 4)
        .opacity(set.status.isSkipped ? 0.6 : 1)
        .sensoryFeedback(.success, trigger: isRecord) { old, new in !old && new }
    }

    @ViewBuilder
    private var valueText: some View {
        if isRunning, let timer = session.workout.timer {
            Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentColor)
        } else {
            Text(Format.value(set.value, unit: unit))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if set.status.isLogged {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(L10n.workoutLogged)
        } else if kind == .duration {
            if isRunning {
                Button {
                    session.send(.stopWork)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 34))
                }
                .accessibilityLabel(L10n.workoutStopTimer)
                .accessibilityIdentifier("workout.stop")
            } else {
                Button {
                    session.send(.startWork(set.id))
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                }
                .accessibilityLabel(L10n.workoutStartTimer)
                .accessibilityIdentifier("workout.start")
            }
        } else {
            Button {
                // Apply a number still being typed (it is saved as soon as focus leaves).
                focus.wrappedValue = nil
                session.send(.logSet(set.id))
                editing = false
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 34))
                    .foregroundStyle(isNext ? Color.accentColor : Color.secondary)
            }
            .accessibilityLabel(L10n.workoutLogSet)
            .accessibilityIdentifier("workout.log")
        }
    }

    private var rowMenu: some View {
        Menu {
            if set.status.isPending {
                Button {
                    session.send(.skipSet(set.id))
                } label: {
                    Label(L10n.workoutSkipSet, systemImage: "forward")
                }
            }
            if !set.status.isLogged, canRemove {
                Button(role: .destructive) {
                    session.send(.removeSet(set.id))
                } label: {
                    Label(L10n.workoutRemoveSet, systemImage: "minus.circle")
                }
            }
            Button {
                editing.toggle()
            } label: {
                Label(L10n.edit, systemImage: "slider.horizontal.3")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel(L10n.more)
    }

    /// Two equal, centered columns. Tap a number to type it; − and + make small changes.
    @ViewBuilder
    private var controls: some View {
        switch set.value {
        case .reps(let count, let weight):
            HStack(spacing: 12) {
                NumberStepper(
                    title: L10n.repsText,
                    value: Binding(
                        get: { Double(count) },
                        set: { update(set.value.withReps(Int(min(max($0, 0), 999)))) }
                    ),
                    step: 1, fractionDigits: 0, keyboard: .numberPad,
                    focus: focus, field: SetField(set: set.id, kind: .reps), identifier: "set.reps"
                )
                NumberStepper(
                    title: L10n.weightIn(unit == .kilograms ? L10n.unitKg : L10n.unitLb),
                    value: Binding(
                        get: { (weight ?? .zero).value(in: unit) },
                        // Capped before conversion; the set clamps to its real limit.
                        set: { update(set.value.withWeight(Mass(min(max($0, 0), 2_500), unit: unit))) }
                    ),
                    step: unit.increment, fractionDigits: 2, keyboard: .decimalPad,
                    focus: focus, field: SetField(set: set.id, kind: .weight), identifier: "set.weight"
                )
            }
        case .duration(let seconds):
            NumberStepper(
                title: L10n.secondsLabel,
                value: Binding(
                    get: { Double(seconds) },
                    set: { update(set.value.withSeconds(Int(min(max($0, 1), 3600)), range: Limits.loggedSeconds)) }
                ),
                step: 5, fractionDigits: 0, keyboard: .numberPad,
                focus: focus, field: SetField(set: set.id, kind: .seconds), identifier: "set.seconds"
            )
        }
    }

    private func update(_ value: SetValue) {
        session.send(.setValue(set.id, value))
    }
}

/// A small trophy tag on a set that beat the exercise's history.
private struct RecordBadge: View {
    var body: some View {
        Label(L10n.recordsBadge, systemImage: "trophy.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workout.record")
    }
}

/// Shown when notifications are declined: timers still run, but only alert inside the app.
private struct AlertsOffRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.secondary)
            Text(L10n.alertsOff)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button(L10n.openSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }
}

/// Which number field is being typed into: one per set and value.
struct SetField: Hashable {
    enum Kind: Hashable { case reps, weight, seconds }
    let set: UUID
    let kind: Kind
}

/// A label, then [−] typeable number [+]. Typing handles big jumps (120 kg); the buttons
/// handle small ones. Tapping the number empties it (the old value stays as a grey hint), so
/// typing replaces it; the value is applied when the field loses focus. Empty keeps the old value.
struct NumberStepper: View {
    let title: String
    @Binding var value: Double
    let step: Double
    let fractionDigits: Int
    let keyboard: UIKeyboardType
    let focus: FocusState<SetField?>.Binding
    let field: SetField
    let identifier: String
    @State private var text = ""

    private var isFocused: Bool { focus.wrappedValue == field }
    private var formatted: String { value.formatted(.number.precision(.fractionLength(0...fractionDigits))) }

    private func commit() {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty, let number = try? Double(typed, format: .number) {
            value = number
        }
        text = formatted
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    value = max(0, value - step)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.decrease)

                TextField(title, text: $text, prompt: Text(formatted))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .frame(width: 64)
                    .focused(focus, equals: field)
                    .accessibilityIdentifier(identifier)
                    .onAppear { text = formatted }
                    .onChange(of: isFocused) { _, focused in
                        if focused { text = "" } else { commit() }
                    }
                    // Typed numbers apply right away, so a Save or log tapped mid-typing keeps them.
                    .onChange(of: text) { _, typed in
                        guard isFocused, let number = try? Double(typed.trimmingCharacters(in: .whitespaces), format: .number) else { return }
                        value = number
                    }
                    .onChange(of: value) { _, _ in
                        if !isFocused { text = formatted }
                    }

                Button {
                    value += step
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.increase)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The pinned rest or exercise countdown. Remaining time is drawn by the system from the
/// deadline, so it stays right without per-second updates.
private struct TimerBar: View {
    let timer: ActiveTimer
    let session: WorkoutSession

    var body: some View {
        VStack(spacing: 10) {
            Text(timer.isRest ? L10n.timerRest : L10n.timerWork)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(timerInterval: timer.startedAt...timer.endsAt, countsDown: true)
                .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                .frame(maxWidth: .infinity)
            ProgressView(timerInterval: timer.startedAt...timer.endsAt, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            if timer.isRest {
                HStack(spacing: 12) {
                    Button(L10n.timerMinus) { session.send(.adjustRest(seconds: -15)) }
                        .buttonStyle(.bordered)
                    Button {
                        session.send(.skipRest)
                    } label: {
                        Text(L10n.timerSkip)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("timer.skip")
                    Button(L10n.timerPlus) { session.send(.adjustRest(seconds: 15)) }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
            } else {
                Button {
                    session.send(.stopWork)
                } label: {
                    Text(L10n.workoutStopTimer)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct WorkoutSummaryView: View {
    let workout: Workout
    @Environment(AppModel.self) private var model
    /// The new plan being named in the plan editor.
    @State private var draft: Plan?
    /// The plan made from this workout; it exists once the editor saved it.
    @State private var draftID: PlanID?
    @State private var updatedPlan = false

    var body: some View {
        NavigationStack {
            WorkoutResultsList(workout: workout) {
                newRecords
                planActions
            }
            .navigationTitle(L10n.summaryTitle)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) { model.closeFinishedSession() }
                        .accessibilityIdentifier("summary.done")
                }
            }
            .sheet(item: $draft) { draft in
                PlanEditorView(plan: draft, isNew: true)
            }
        }
    }

    /// The best record each exercise broke in this workout, if any.
    @ViewBuilder private var newRecords: some View {
        let found = workout.exercises.compactMap { exercise -> (id: UUID, name: String, record: PersonalRecord)? in
            let logged = exercise.sets.filter { $0.status.isLogged }.map(\.value)
            guard let best = model.records(of: exercise.exercise, excluding: workout.id).broken(bySession: logged).first else { return nil }
            return (exercise.id, model.name(of: exercise.exercise, snapshot: exercise.nameSnapshot), best)
        }
        if !found.isEmpty {
            Section(L10n.recordsNew) {
                ForEach(found, id: \.id) { item in
                    let text = Format.record(item.record, unit: model.weightUnit)
                    LabeledContent {
                        Text(text.value)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(text.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityIdentifier("summary.record")
                }
            }
        }
    }

    /// Offered after an empty workout, or when the exercises or their order changed.
    @ViewBuilder private var planActions: some View {
        let plan = workout.planID.flatMap { model.plan($0) }
        let changed = plan.map { workout.changesExercises(of: $0) } ?? true
        if !workout.exercises.isEmpty, changed || updatedPlan {
            Section {
                if let plan {
                    if updatedPlan {
                        Label(L10n.summaryPlanUpdated, systemImage: "checkmark")
                    } else {
                        Button(L10n.summaryUpdatePlan(plan.name)) {
                            model.updatePlan(plan, from: workout)
                            updatedPlan = true
                        }
                        .accessibilityIdentifier("summary.updatePlan")
                    }
                }
                if let draftID, model.plan(draftID) != nil {
                    Label(L10n.summarySavedAsPlan, systemImage: "checkmark")
                } else {
                    Button(L10n.summarySaveAsPlan) {
                        let new = model.planDraft(from: workout)
                        draftID = new.id
                        draft = new
                    }
                    .accessibilityIdentifier("summary.saveAsPlan")
                }
            }
        }
    }
}

/// The live heart rate from the Bluetooth sensor, or a dash while searching or out of range.
struct HeartRateReading: View {
    let bpm: Int?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: bpm == nil ? "heart.slash" : "heart.fill")
                .foregroundStyle(bpm == nil ? Color.secondary : Color.red)
            if let bpm {
                Text(L10n.bpm(bpm))
            } else {
                Text(verbatim: "–")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map(L10n.heartRateValue) ?? L10n.heartRateUnavailable)
        .accessibilityIdentifier("workout.heartRate")
    }
}
