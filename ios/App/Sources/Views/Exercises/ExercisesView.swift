import AmmuttaCore
import Charts
import SwiftUI

struct ExercisesView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                let custom = model.entries(model.customEntries, matching: query)
                if !custom.isEmpty {
                    Section(L10n.exercisesCustom) {
                        ForEach(custom) { entry in
                            NavigationLink(value: entry.ref) { ExerciseEntryRow(entry: entry) }
                        }
                    }
                }
                Section(L10n.exercisesBuiltIn) {
                    ForEach(model.entries(model.builtInEntries, matching: query)) { entry in
                        NavigationLink(value: entry.ref) { ExerciseEntryRow(entry: entry) }
                            .accessibilityIdentifier("exercises.builtIn")
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle(L10n.tabExercises)
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(ref: ref)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label(L10n.exercisesNew, systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseEditor(existing: nil) { _ in }
            }
        }
    }
}

struct ExerciseEntryRow: View {
    let entry: ExerciseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.name)
            HStack(spacing: 6) {
                Text(entry.detail)
                Text(verbatim: "·")
                Text(entry.kind == .reps ? L10n.kindReps : L10n.kindDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Picks one exercise for a plan, or creates a custom one inline.
struct ExercisePickerView: View {
    let onPick: (ExerciseRef, TrackingKind) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.entries(model.customEntries + model.builtInEntries, matching: query).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { entry in
                    Button {
                        onPick(entry.ref, entry.kind)
                        dismiss()
                    } label: {
                        ExerciseEntryRow(entry: entry)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("picker.\(entry.testIdentifier)")
                }
            }
            .searchable(text: $query)
            .navigationTitle(L10n.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        creating = true
                    } label: {
                        Label(L10n.exercisesNew, systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $creating) {
                CustomExerciseEditor(existing: nil) { saved in
                    onPick(saved.ref, saved.kind)
                    dismiss()
                }
            }
        }
    }
}

struct ExerciseDetailView: View {
    let ref: ExerciseRef
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CustomExercise?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section {
                if let entry = model.entry(for: ref) {
                    LabeledContent(L10n.exerciseKind, value: entry.kind == .reps ? L10n.kindRepsText : L10n.kindDurationText)
                }
                if case .builtIn(let key) = ref, let builtIn = ExerciseCatalog.exercise(forKey: key) {
                    LabeledContent(L10n.exerciseEquipment, value: ExerciseText.equipment(builtIn.equipment))
                }
            }
            if case .builtIn(let key) = ref {
                Section(L10n.exerciseMuscles) {
                    Text(ExerciseText.muscles(key))
                        .accessibilityIdentifier("exercise.muscles")
                }
                Section(L10n.exerciseTechnique) {
                    Text(ExerciseText.tip(key))
                }
            }

            let sessions = model.sessions(of: ref)
            RecordsSections(records: ExerciseRecords(sessions: sessions), estimates: ExerciseProgress.estimates(sessions))
            if let last = sessions.first {
                Section(L10n.exerciseLast) {
                    ForEach(Array(last.results.enumerated()), id: \.offset) { index, result in
                        LabeledContent(L10n.setNumber(index + 1), value: Format.value(result, unit: model.weightUnit))
                    }
                }
            }
            Section(L10n.exerciseHistory) {
                if sessions.isEmpty {
                    Text(L10n.exerciseNoHistory)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.date, format: .dateTime.day().month().year())
                                .font(.subheadline.weight(.semibold))
                            Text(session.results.map { Format.value($0, unit: model.weightUnit) }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(model.name(of: ref))
        .toolbar {
            if case .custom(let id) = ref, let custom = model.customExercise(id) {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.edit) { editing = custom }
                }
                if !model.isUsed(ref) {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sheet(item: $editing) { custom in
            CustomExerciseEditor(existing: custom) { _ in }
        }
        .alert(L10n.exerciseDeleteTitle, isPresented: $confirmingDelete) {
            Button(L10n.delete, role: .destructive) {
                if case .custom(let id) = ref, let custom = model.customExercise(id) {
                    model.delete(custom)
                }
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        }
    }
}

/// An exercise's bests: the headline records, the estimated 1RM over time, and the heaviest
/// weight for each rep count. Nothing shows before there's history.
private struct RecordsSections: View {
    let records: ExerciseRecords
    let estimates: [(date: Date, estimate: Mass)]
    @Environment(AppModel.self) private var model

    private var unit: WeightUnit { model.weightUnit }

    var body: some View {
        if !records.isEmpty {
            Section(L10n.recordsTitle) {
                if let estimate = records.bestEstimate {
                    LabeledContent(L10n.recordsEstimate, value: Format.mass(estimate, unit: unit))
                }
                if let heaviest = records.heaviest {
                    LabeledContent(L10n.recordsHeaviest, value: Format.mass(heaviest, unit: unit))
                }
                if let volume = records.bestVolumeGrams {
                    LabeledContent(L10n.recordsVolume, value: Format.mass(Mass(grams: volume), unit: unit))
                }
                if let reps = records.mostReps {
                    LabeledContent(L10n.recordsMostReps, value: L10n.repsCount(reps))
                }
                if let seconds = records.longestSeconds {
                    LabeledContent(L10n.recordsLongest, value: Format.clock(seconds))
                }
            }
            .accessibilityIdentifier("exercise.records")
        }
        if estimates.count > 1 {
            Section(L10n.recordsEstimate) {
                Chart(Array(estimates.enumerated()), id: \.offset) { item in
                    LineMark(
                        x: .value(L10n.chartTime, item.element.date),
                        y: .value(L10n.recordsEstimate, item.element.estimate.value(in: unit))
                    )
                    PointMark(
                        x: .value(L10n.chartTime, item.element.date),
                        y: .value(L10n.recordsEstimate, item.element.estimate.value(in: unit))
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                .padding(.vertical, 8)
            }
        }
        if !records.bestByReps.isEmpty {
            Section(L10n.recordsByReps) {
                ForEach(records.bestByReps.keys.sorted(), id: \.self) { reps in
                    if let weight = records.bestByReps[reps] {
                        LabeledContent(L10n.repsCount(reps), value: Format.mass(weight, unit: unit))
                    }
                }
            }
        }
    }
}

struct CustomExerciseEditor: View {
    let existing: CustomExercise?
    let onSave: (CustomExercise) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: TrackingKind

    init(existing: CustomExercise?, onSave: @escaping (CustomExercise) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .reps)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicate: Bool { model.isDuplicateName(trimmedName, kind: kind, excluding: existing?.id) }
    private var kindLocked: Bool { existing.map { model.isUsed($0.ref) } ?? false }
    private var canSave: Bool { !trimmedName.isEmpty && trimmedName.count <= Limits.nameLength.upperBound && !isDuplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.exerciseName, text: $name)
                    Picker(L10n.exerciseKind, selection: $kind) {
                        Text(L10n.kindReps).tag(TrackingKind.reps)
                        Text(L10n.kindDuration).tag(TrackingKind.duration)
                    }
                    .disabled(kindLocked)
                } footer: {
                    if isDuplicate {
                        Text(L10n.exerciseDuplicate)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? L10n.exercisesNew : L10n.exerciseEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        var exercise = existing ?? CustomExercise(name: trimmedName, kind: kind, createdAt: .now)
        exercise.name = trimmedName
        if !kindLocked { exercise.kind = kind }
        model.save(exercise)
        onSave(exercise)
        dismiss()
    }
}
