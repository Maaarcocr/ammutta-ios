import AmmuttaCore
import Charts
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingDelete: Workout?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.historyByMonth) { group in
                    Section {
                        ForEach(group.workouts) { workout in
                            NavigationLink(value: workout.id) {
                                HistoryRow(workout: workout)
                            }
                            .accessibilityIdentifier("history.row")
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = workout
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.month, format: .dateTime.month(.wide).year())
                    }
                }
            }
            .overlay {
                if model.history.isEmpty {
                    ContentUnavailableView(L10n.historyEmpty, systemImage: "clock.arrow.circlepath")
                }
            }
            .navigationTitle(L10n.tabHistory)
            .navigationDestination(for: WorkoutID.self) { id in
                WorkoutDetailView(workoutID: id)
            }
            .alert(
                L10n.historyDeleteTitle,
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                presenting: pendingDelete
            ) { workout in
                Button(L10n.delete, role: .destructive) {
                    model.deleteWorkout(workout.id)
                }
                Button(L10n.cancel, role: .cancel) {}
            }
        }
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let workout: Workout

    var body: some View {
        let summary = WorkoutSummary(workout)
        VStack(alignment: .leading, spacing: 4) {
            Text(workout.planName)
                .font(.headline)
            Text(workout.startedAt, format: .dateTime.weekday(.wide).day().hour().minute())
                .font(.subheadline)
            Text(SummaryText.line(summary, unit: model.weightUnit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

enum SummaryText {
    /// "52 min · 14/15 · 4,320 kg"
    static func line(_ summary: WorkoutSummary, unit: WeightUnit) -> String {
        var parts = [Format.workoutDuration(summary.durationSeconds), L10n.fraction(summary.loggedSets, summary.totalSets)]
        if summary.volumeGrams > 0 {
            parts.append(Format.mass(Mass(grams: summary.volumeGrams), unit: unit))
        }
        return parts.joined(separator: " · ")
    }
}

struct WorkoutDetailView: View {
    let workoutID: WorkoutID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var editing: Workout?

    var body: some View {
        if let workout = model.workout(workoutID) {
            WorkoutResultsList(workout: workout)
                .navigationTitle(workout.planName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.edit) { editing = workout }
                            .accessibilityIdentifier("history.edit")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                    }
                }
                .sheet(item: $editing) { workout in
                    WorkoutEditorView(workout: workout)
                }
                .alert(L10n.historyDeleteTitle, isPresented: $confirmingDelete) {
                    Button(L10n.delete, role: .destructive) {
                        model.deleteWorkout(workoutID)
                        dismiss()
                    }
                    Button(L10n.cancel, role: .cancel) {}
                }
        }
    }
}

/// Corrections to a finished workout, laid out like the workout screen: each set is a compact
/// row ("8 × 60 kg") with a done circle; tapping it opens the same − value + controls.
struct WorkoutEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var workout: Workout
    @State private var endedAt: Date
    /// Sets showing their controls.
    @State private var expanded: Set<UUID> = []
    @FocusState private var focusedField: SetField?

    init(workout: Workout) {
        _workout = State(initialValue: workout)
        _endedAt = State(initialValue: workout.endedAt ?? workout.startedAt)
    }

    private var edited: Workout {
        var edited = workout
        edited.endedAt = endedAt
        return edited
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(L10n.historyEditStart, selection: $workout.startedAt)
                    DatePicker(L10n.historyEditEnd, selection: $endedAt, in: workout.startedAt...)
                }
                ForEach($workout.exercises) { $exercise in
                    Section(model.name(of: exercise.exercise, snapshot: exercise.nameSnapshot)) {
                        ForEach($exercise.sets) { $set in
                            EditableSetRow(
                                number: (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1,
                                set: $set,
                                isExpanded: expanded.contains(set.id),
                                toggle: { toggle(set.id) },
                                doneAt: endedAt,
                                focus: $focusedField
                            )
                        }
                        .onDelete { offsets in
                            guard exercise.sets.count - offsets.count >= Limits.setsPerExercise.lowerBound else { return }
                            exercise.sets.remove(atOffsets: offsets)
                        }
                        Button {
                            let value = exercise.sets.last?.value ?? .defaultValue(for: exercise.kind)
                            let added = WorkoutSet(target: value, value: value, status: .logged(at: endedAt))
                            exercise.sets.append(added)
                            expanded = [added.id]
                        } label: {
                            Label(L10n.addSet, systemImage: "plus")
                        }
                        .disabled(exercise.sets.count >= Limits.setsPerExercise.upperBound)
                        .accessibilityIdentifier("edit.addSet")
                    }
                }
            }
            .navigationTitle(L10n.historyEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        model.updateFinishedWorkout(edited)
                        dismiss()
                    }
                    .disabled(!edited.isValidFinished)
                    .accessibilityIdentifier("edit.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.done) { focusedField = nil }
                        .accessibilityIdentifier("keyboard.done")
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

/// One set in the workout editor: its number, its value (tap to change it) and whether it was done.
private struct EditableSetRow: View {
    let number: Int
    @Binding var set: WorkoutSet
    let isExpanded: Bool
    let toggle: () -> Void
    /// When a set newly marked as done counts as logged.
    let doneAt: Date
    let focus: FocusState<SetField?>.Binding
    @Environment(AppModel.self) private var model

    private var unit: WeightUnit { model.weightUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(number, format: .number)
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 24)
                    .foregroundStyle(.secondary)
                Button(action: toggle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Format.value(set.value, unit: unit))
                            .font(.title3.weight(.semibold).monospacedDigit())
                        if !set.status.isLogged {
                            Text(L10n.notDone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("edit.set")
                Button {
                    set.status = set.status.isLogged ? .pending : .logged(at: doneAt)
                } label: {
                    Image(systemName: set.status.isLogged ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 30))
                        .foregroundStyle(set.status.isLogged ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.historyEditSetDone)
                .accessibilityValue(set.status.isLogged ? L10n.workoutLogged : L10n.notDone)
                .accessibilityIdentifier("edit.setDone")
            }
            if isExpanded {
                controls
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var controls: some View {
        switch set.value {
        case .reps(let count, let weight):
            HStack(spacing: 12) {
                NumberStepper(
                    title: L10n.repsText,
                    value: Binding(
                        get: { Double(count) },
                        set: { set.value = set.value.withReps(Int(min(max($0, 0), 999))) }
                    ),
                    step: 1, fractionDigits: 0, keyboard: .numberPad,
                    focus: focus, field: SetField(set: set.id, kind: .reps), identifier: "edit.reps"
                )
                NumberStepper(
                    title: L10n.weightIn(unit == .kilograms ? L10n.unitKg : L10n.unitLb),
                    value: Binding(
                        get: { (weight ?? .zero).value(in: unit) },
                        set: { set.value = set.value.withWeight(Mass(min(max($0, 0), 2_500), unit: unit)) }
                    ),
                    step: unit.increment, fractionDigits: 2, keyboard: .decimalPad,
                    focus: focus, field: SetField(set: set.id, kind: .weight), identifier: "edit.weight"
                )
            }
        case .duration(let seconds):
            NumberStepper(
                title: L10n.secondsLabel,
                value: Binding(
                    get: { Double(seconds) },
                    set: { set.value = set.value.withSeconds(Int(min(max($0, 1), 3600)), range: Limits.loggedSeconds) }
                ),
                step: 5, fractionDigits: 0, keyboard: .numberPad,
                focus: focus, field: SetField(set: set.id, kind: .seconds), identifier: "edit.seconds"
            )
        }
    }
}

/// The summary numbers plus every set of a workout. Shared by the finish screen (which adds its
/// actions below the numbers) and history.
struct WorkoutResultsList<Actions: View>: View {
    @Environment(AppModel.self) private var model
    let workout: Workout
    let actions: Actions

    init(workout: Workout, @ViewBuilder actions: () -> Actions) {
        self.workout = workout
        self.actions = actions()
    }

    var body: some View {
        let summary = WorkoutSummary(workout)
        List {
            Section {
                LabeledContent(L10n.summaryDuration, value: Format.workoutDuration(summary.durationSeconds))
                LabeledContent(L10n.summarySets, value: L10n.fraction(summary.loggedSets, summary.totalSets))
                if summary.volumeGrams > 0 {
                    LabeledContent(L10n.summaryVolume, value: Format.mass(Mass(grams: summary.volumeGrams), unit: model.weightUnit))
                }
                if let average = summary.averageHeartRate, let maximum = summary.maxHeartRate {
                    LabeledContent(L10n.summaryHeartRateAverage, value: L10n.bpm(average))
                    LabeledContent(L10n.summaryHeartRateMax, value: L10n.bpm(maximum))
                }
            } header: {
                Text(workout.startedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
            }
            actions
            if workout.heartRate.count > 1 {
                Section(L10n.summaryHeartRate) {
                    HeartRateChart(samples: workout.heartRate)
                }
            }
            ForEach(workout.exercises) { exercise in
                Section(model.name(of: exercise.exercise, snapshot: exercise.nameSnapshot)) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text(L10n.setNumber(index + 1))
                                .foregroundStyle(.secondary)
                            Spacer()
                            switch set.status {
                            case .logged(let date):
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Format.value(set.value, unit: model.weightUnit))
                                    Text(date, format: .dateTime.hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            case .skipped:
                                Text(L10n.skipped).foregroundStyle(.secondary)
                            case .pending:
                                Text(L10n.notDone).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

extension WorkoutResultsList where Actions == EmptyView {
    init(workout: Workout) {
        self.init(workout: workout) { EmptyView() }
    }
}

/// Heart rate over the workout.
struct HeartRateChart: View {
    let samples: [HeartRateSample]

    var body: some View {
        Chart(samples, id: \.date) { sample in
            LineMark(
                x: .value(L10n.chartTime, sample.date),
                y: .value(L10n.chartHeartRate, sample.bpm)
            )
            .foregroundStyle(.red)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 160)
        .padding(.vertical, 8)
    }
}
