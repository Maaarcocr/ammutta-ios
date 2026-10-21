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
