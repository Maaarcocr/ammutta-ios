import AmmuttaCore
import SwiftUI

/// The active workout: one scrolling dashboard of exercises, with the current one
/// expanded and the rest or exercise countdown pinned to the bottom.
struct WorkoutView: View {
    let session: WorkoutSession
    @Environment(AppModel.self) private var model
    @State private var confirmingDiscard = false
    @State private var toggled: Set<UUID> = []

    var body: some View {
        @Bindable var model = model
        Group {
            if session.isFinished {
                WorkoutSummaryView(workout: session.workout)
            } else {
                active
            }
        }
        .sheet(item: $model.importRequest) { request in
            PlanImportSheet(request: request)
                .environment(model)
        }
    }

    private var currentExerciseID: UUID? {
        guard let setID = session.workout.nextPendingSetID,
              let location = session.workout.location(ofSet: setID) else { return nil }
        return session.workout.exercises[location.exercise].id
    }

    private var active: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(session.workout.exercises) { exercise in
                        let isCurrent = exercise.id == currentExerciseID
                        ExerciseCard(
                            exercise: exercise,
                            session: session,
                            isExpanded: isCurrent != toggled.contains(exercise.id),
                            toggle: { toggle(exercise.id) }
                        )
                    }
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
                        Button(role: .destructive) {
                            confirmingDiscard = true
                        } label: {
                            Label(L10n.workoutDiscard, systemImage: "trash")
                        }
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
                        Text(session.workout.startedAt, style: .timer)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.workoutFinish) {
                        session.send(.finish)
                    }
                    .accessibilityIdentifier("workout.finish")
                }
            }
            .confirmationDialog(L10n.workoutDiscardTitle, isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button(L10n.workoutDiscard, role: .destructive) {
                    model.discardActiveWorkout()
                }
            }
            .sensoryFeedback(.success, trigger: session.timerEndedCount)
        }
    }

    /// Tapping a header flips it away from its default (current = open, others = closed).
    private func toggle(_ id: UUID) {
        if toggled.contains(id) { toggled.remove(id) } else { toggled.insert(id) }
    }
}

private struct ExerciseCard: View {
    let exercise: WorkoutExercise
    let session: WorkoutSession
    let isExpanded: Bool
    let toggle: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if isExpanded {
                let last = model.lastPerformance(of: exercise.exercise)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                    Divider()
                    SetRow(
                        set: set,
                        number: setIndex + 1,
                        kind: exercise.kind,
                        last: last?.results[safe: setIndex],
                        isNext: set.id == session.workout.nextPendingSetID,
                        canRemove: exercise.sets.count > 1,
                        session: session
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
}

private struct SetRow: View {
    let set: WorkoutSet
    let number: Int
    let kind: TrackingKind
    let last: SetValue?
    let isNext: Bool
    let canRemove: Bool
    let session: WorkoutSession
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
                        valueText
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
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 4)
        .opacity(set.status.isSkipped ? 0.6 : 1)
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

    @ViewBuilder
    private var controls: some View {
        switch set.value {
        case .reps(let count, let weight):
            HStack(spacing: 20) {
                // Just the number: the row above already says "8 reps", and the
                // Italian "ripetizioni" doesn't fit next to the +/- buttons.
                ValueStepper(text: count.formatted(),
                             decrement: { update(set.value.withReps(count - 1)) },
                             increment: { update(set.value.withReps(count + 1)) })
                ValueStepper(text: Format.mass(weight ?? .zero, unit: unit),
                             decrement: { update(set.value.withWeight((weight ?? .zero).adding(-unit.increment, unit: unit))) },
                             increment: { update(set.value.withWeight((weight ?? .zero).adding(unit.increment, unit: unit))) })
            }
        case .duration(let seconds):
            ValueStepper(text: Format.clock(seconds),
                         decrement: { update(set.value.withSeconds(seconds - 5, range: Limits.loggedSeconds)) },
                         increment: { update(set.value.withSeconds(seconds + 5, range: Limits.loggedSeconds)) })
        }
    }

    private func update(_ value: SetValue) {
        session.send(.setValue(set.id, value))
    }
}

/// [−] value [+] with large, one-handed tap targets.
private struct ValueStepper: View {
    let text: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: decrement) {
                Image(systemName: "minus")
                    .frame(width: 20, height: 20)
            }
            .accessibilityLabel(L10n.decrease)
            Text(text)
                .font(.body.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 64)
            Button(action: increment) {
                Image(systemName: "plus")
                    .frame(width: 20, height: 20)
            }
            .accessibilityLabel(L10n.increase)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
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
                            .foregroundStyle(Color("OnAccent"))
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
                        .foregroundStyle(Color("OnAccent"))
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

    var body: some View {
        NavigationStack {
            WorkoutResultsList(workout: workout)
                .navigationTitle(L10n.summaryTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.done) { model.closeFinishedSession() }
                            .accessibilityIdentifier("summary.done")
                    }
                }
        }
    }
}
