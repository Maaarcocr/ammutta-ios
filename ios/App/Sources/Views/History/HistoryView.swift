import AmmuttaCore
import Charts
import SwiftUI

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

    var body: some View {
        if let workout = model.workout(workoutID) {
            WorkoutResultsList(workout: workout)
                .navigationTitle(workout.planName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                    }
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
