import AmmuttaCore
import SwiftUI

struct PlanEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var plan: Plan
    @State private var pickingExercise = false
    let isNew: Bool

    init(plan: Plan, isNew: Bool) {
        _plan = State(initialValue: plan)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.planEditorName, text: $plan.name)
                        .accessibilityIdentifier("planEditor.name")
                }
                Section(L10n.planExercises) {
                    ForEach($plan.exercises) { $exercise in
                        NavigationLink {
                            PlanExerciseEditor(exercise: $exercise)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name(of: exercise.exercise))
                                Text(Format.setsSummary(exercise.sets, unit: model.weightUnit))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { plan.exercises.remove(atOffsets: $0) }
                    .onMove { plan.exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        pickingExercise = true
                    } label: {
                        Label(L10n.planEditorAddExercise, systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("planEditor.addExercise")
                }
            }
            .navigationTitle(isNew ? L10n.planEditorNewTitle : L10n.planEditorEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { save() }
                        .disabled(!plan.isValid)
                        .accessibilityIdentifier("planEditor.save")
                }
            }
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerView { ref, kind in
                    plan.exercises.append(.make(exercise: ref, kind: kind, restSeconds: model.defaultRestSeconds))
                }
            }
        }
    }

    private func save() {
        var saved = plan
        saved.name = plan.name.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.updatedAt = .now
        model.save(saved)
        dismiss()
    }
}

/// Rest time and per-set targets for one exercise in a plan.
struct PlanExerciseEditor: View {
    @Binding var exercise: PlanExercise
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Stepper(value: $exercise.restSeconds, in: Limits.restSeconds, step: 15) {
                    LabeledContent(L10n.rest, value: Format.clock(exercise.restSeconds))
                }
            }
            Section(L10n.sets) {
                ForEach(exercise.sets.indices, id: \.self) { index in
                    SetTargetEditor(number: index + 1, value: binding(for: index), unit: model.weightUnit)
                }
                .onDelete { offsets in
                    guard exercise.sets.count - offsets.count >= Limits.setsPerExercise.lowerBound else { return }
                    exercise.sets.remove(atOffsets: offsets)
                }

                Button {
                    guard exercise.sets.count < Limits.setsPerExercise.upperBound else { return }
                    exercise.sets.append(exercise.sets.last ?? .defaultValue(for: exercise.kind))
                } label: {
                    Label(L10n.addSet, systemImage: "plus")
                }
                .disabled(exercise.sets.count >= Limits.setsPerExercise.upperBound)

                Button {
                    guard let first = exercise.sets.first else { return }
                    exercise.sets = Array(repeating: first, count: exercise.sets.count)
                } label: {
                    Label(L10n.applyToAll, systemImage: "square.stack")
                }
                .disabled(exercise.sets.count < 2)
            }
        }
        .navigationTitle(model.name(of: exercise.exercise))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Bounds-checked, so a row being deleted never reads past the end of the array.
    private func binding(for index: Int) -> Binding<SetValue> {
        Binding(
            get: { exercise.sets[safe: index] ?? .defaultValue(for: exercise.kind) },
            set: { newValue in
                if exercise.sets.indices.contains(index) { exercise.sets[index] = newValue }
            }
        )
    }
}

/// Reps and weight, or a duration, for one set. Used by the plan editor and the workout editor.
struct SetTargetEditor: View {
    let number: Int
    @Binding var value: SetValue
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.setNumber(number))
                .font(.subheadline.weight(.semibold))
            switch value {
            case .reps(let count, let weight):
                Stepper(value: Binding(get: { count }, set: { value = value.withReps($0) }), in: Limits.reps) {
                    Text(L10n.repsCount(count))
                }
                HStack {
                    Text(L10n.weight)
                    Spacer()
                    TextField(
                        L10n.weight,
                        value: Binding(
                            get: { weight?.value(in: unit) ?? 0 },
                            set: { value = value.withWeight($0 > 0 ? Mass($0, unit: unit) : nil) }
                        ),
                        format: .number.precision(.fractionLength(0...2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 96)
                    Text(unit == .kilograms ? L10n.unitKg : L10n.unitLb)
                        .foregroundStyle(.secondary)
                }
            case .duration(let seconds):
                Stepper(value: Binding(get: { seconds }, set: { value = value.withSeconds($0) }), in: Limits.targetSeconds, step: 5) {
                    LabeledContent(L10n.duration, value: Format.clock(seconds))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
