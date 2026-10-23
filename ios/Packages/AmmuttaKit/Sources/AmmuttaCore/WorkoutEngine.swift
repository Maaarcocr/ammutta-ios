import Foundation

/// Everything the user (or the clock) can do to an active workout.
public enum WorkoutEvent: Hashable, Sendable {
    /// Log a pending or skipped set at its current value. Ends any timer and starts rest.
    case logSet(UUID)
    /// Change a set's value (before or after logging).
    case setValue(UUID, SetValue)
    case skipSet(UUID)
    /// Append a set to an exercise, copying the previous set.
    case addSet(exercise: UUID, newSetID: UUID)
    /// Remove a set that hasn't been logged.
    case removeSet(UUID)
    /// Append an exercise whose sets are all pending, valid targets.
    case addExercise(WorkoutExercise)
    /// Swap an exercise with nothing logged for another. Sets of the same kind keep their values;
    /// otherwise each set starts from the default for the new kind.
    case replaceExercise(UUID, with: ExerciseRef, kind: TrackingKind, nameSnapshot: String?)
    /// Remove an exercise with nothing logged.
    case removeExercise(UUID)
    /// Move an exercise to a position in the list (its index once moved).
    case moveExercise(UUID, to: Int)
    /// Start the countdown of a pending duration set.
    case startWork(UUID)
    /// Stop the running countdown early and log the elapsed time.
    case stopWork
    case adjustRest(seconds: Int)
    case skipRest
    /// Resolve a timer whose deadline has passed. Harmless when nothing has expired.
    case timerElapsed
    case finish
}

public enum WorkoutError: Error, Equatable, Sendable {
    case finished
    case unknownSet
    case unknownExercise
    case notAllowed
    case invalidValue
}

/// The workout rules as a pure function: no clock reads, no side effects.
public enum WorkoutEngine {
    public static func reduce(_ workout: Workout, _ event: WorkoutEvent, now: Date) throws(WorkoutError) -> Workout {
        guard workout.endedAt == nil else { throw .finished }
        var w = workout
        // Settle any timer that already ran out, so every event sees a consistent present.
        resolveExpiredTimer(&w, now: now)

        switch event {
        case .timerElapsed:
            break

        case .logSet(let id):
            let (e, s) = try locate(id, in: w)
            guard !w.exercises[e].sets[s].status.isLogged else { throw .notAllowed }
            do { try w.exercises[e].sets[s].value.validateAsResult() } catch { throw .invalidValue }
            w.exercises[e].sets[s].status = .logged(at: now)
            w.timer = nil
            startRest(&w, after: id, exercise: e, from: now, now: now)

        case .setValue(let id, let value):
            let (e, s) = try locate(id, in: w)
            guard value.kind == w.exercises[e].kind else { throw .invalidValue }
            do { try value.validateAsResult() } catch { throw .invalidValue }
            w.exercises[e].sets[s].value = value

        case .skipSet(let id):
            let (e, s) = try locate(id, in: w)
            guard w.exercises[e].sets[s].status.isPending else { throw .notAllowed }
            w.exercises[e].sets[s].status = .skipped(at: now)
            if w.timer?.workSetID == id { w.timer = nil }

        case .addSet(let exerciseID, let newSetID):
            guard let e = w.exercises.firstIndex(where: { $0.id == exerciseID }) else { throw .unknownExercise }
            guard w.exercises[e].sets.count < Limits.setsPerExercise.upperBound else { throw .notAllowed }
            let template = w.exercises[e].sets.last
            let target = template?.target ?? .defaultValue(for: w.exercises[e].kind)
            w.exercises[e].sets.append(WorkoutSet(id: newSetID, target: target, value: template?.value ?? target))

        case .removeSet(let id):
            let (e, s) = try locate(id, in: w)
            guard !w.exercises[e].sets[s].status.isLogged, w.exercises[e].sets.count > 1 else { throw .notAllowed }
            w.exercises[e].sets.remove(at: s)
            if w.timer?.workSetID == id { w.timer = nil }

        case .addExercise(let exercise):
            let setIDs = Set(w.exercises.flatMap { $0.sets.map(\.id) })
            guard !w.exercises.contains(where: { $0.id == exercise.id }),
                  !exercise.sets.contains(where: { setIDs.contains($0.id) }),
                  Limits.setsPerExercise.contains(exercise.sets.count),
                  Limits.restSeconds.contains(exercise.restSeconds)
            else { throw .notAllowed }
            for set in exercise.sets {
                guard set.status.isPending, set.target.kind == exercise.kind, set.value.kind == exercise.kind,
                      set.target.isValidTarget, set.value.isValidTarget
                else { throw .invalidValue }
            }
            w.exercises.append(exercise)

        case .replaceExercise(let id, let ref, let kind, let nameSnapshot):
            let e = try locateExercise(id, in: w)
            guard !w.exercises[e].sets.contains(where: { $0.status.isLogged }) else { throw .notAllowed }
            stopCountdown(&w, inExercise: e)
            let sameKind = w.exercises[e].kind == kind
            w.exercises[e].exercise = ref
            w.exercises[e].kind = kind
            w.exercises[e].nameSnapshot = nameSnapshot
            w.exercises[e].sets = w.exercises[e].sets.map { set in
                let target = sameKind ? set.target : .defaultValue(for: kind)
                return WorkoutSet(id: set.id, target: target, value: sameKind ? set.value : target)
            }

        case .removeExercise(let id):
            let e = try locateExercise(id, in: w)
            guard !w.exercises[e].sets.contains(where: { $0.status.isLogged }) else { throw .notAllowed }
            stopCountdown(&w, inExercise: e)
            w.exercises.remove(at: e)

        case .moveExercise(let id, let index):
            let from = try locateExercise(id, in: w)
            guard w.exercises.indices.contains(index) else { throw .notAllowed }
            let moved = w.exercises.remove(at: from)
            w.exercises.insert(moved, at: index)

        case .startWork(let id):
            let (e, s) = try locate(id, in: w)
            let set = w.exercises[e].sets[s]
            guard set.status.isPending, case .duration(let seconds) = set.value else { throw .notAllowed }
            w.timer = .work(set: id, startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(seconds)))

        case .stopWork:
            guard case .work(let id, let startedAt, _) = w.timer else { throw .notAllowed }
            let (e, s) = try locate(id, in: w)
            let elapsed = Int(now.timeIntervalSince(startedAt).rounded())
            let clamped = min(max(elapsed, Limits.loggedSeconds.lowerBound), Limits.loggedSeconds.upperBound)
            w.exercises[e].sets[s].value = .duration(seconds: clamped)
            w.exercises[e].sets[s].status = .logged(at: now)
            w.timer = nil
            startRest(&w, after: id, exercise: e, from: now, now: now)

        case .adjustRest(let seconds):
            guard case .rest(let after, let startedAt, let endsAt) = w.timer else { throw .notAllowed }
            let newEnd = endsAt.addingTimeInterval(TimeInterval(seconds))
            w.timer = newEnd > now ? .rest(afterSet: after, startedAt: startedAt, endsAt: newEnd) : nil

        case .skipRest:
            guard w.timer?.isRest == true else { throw .notAllowed }
            w.timer = nil

        case .finish:
            w.timer = nil
            w.endedAt = now
        }
        return w
    }

    private static func locateExercise(_ id: UUID, in workout: Workout) throws(WorkoutError) -> Int {
        guard let index = workout.exercises.firstIndex(where: { $0.id == id }) else { throw .unknownExercise }
        return index
    }

    /// A countdown running on one of this exercise's sets stops, because the set is changing or going away.
    private static func stopCountdown(_ w: inout Workout, inExercise e: Int) {
        guard let id = w.timer?.workSetID, w.exercises[e].sets.contains(where: { $0.id == id }) else { return }
        w.timer = nil
    }

    private static func locate(_ id: UUID, in workout: Workout) throws(WorkoutError) -> (Int, Int) {
        guard let location = workout.location(ofSet: id) else { throw .unknownSet }
        return (location.exercise, location.set)
    }

    /// A finished rest just clears. A finished exercise countdown logs its set at the
    /// moment it ended, then starts rest from that moment (which may itself be over
    /// if the app was not running).
    static func resolveExpiredTimer(_ w: inout Workout, now: Date) {
        guard let timer = w.timer, timer.endsAt <= now else { return }
        w.timer = nil
        guard case .work(let id, _, let endsAt) = timer,
              let location = w.location(ofSet: id),
              w.exercises[location.exercise].sets[location.set].status.isPending
        else { return }
        w.exercises[location.exercise].sets[location.set].status = .logged(at: endsAt)
        startRest(&w, after: id, exercise: location.exercise, from: endsAt, now: now)
    }

    /// Rest uses the logged exercise's rest time. Nothing left to do means no rest.
    static func startRest(_ w: inout Workout, after id: UUID, exercise: Int, from start: Date, now: Date) {
        let rest = w.exercises[exercise].restSeconds
        guard rest > 0, w.hasPendingSets else { return }
        let end = start.addingTimeInterval(TimeInterval(rest))
        guard end > now else { return }
        w.timer = .rest(afterSet: id, startedAt: start, endsAt: end)
    }
}
