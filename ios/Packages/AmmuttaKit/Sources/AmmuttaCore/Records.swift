import Foundation

/// The estimated heaviest single (one-rep max) for a set, with the Epley formula:
/// weight × (1 + reps ÷ 30). A single counts as itself. Sets above 10 reps give no estimate,
/// because the formula drifts there; bodyweight and timed sets have none.
public enum OneRepMax {
    public static let maxReps = 10

    public static func estimate(_ value: SetValue) -> Mass? {
        guard case .reps(let reps, let weight?) = value, weight.grams > 0, (1...maxReps).contains(reps) else { return nil }
        if reps == 1 { return weight }
        return Mass(grams: Int((Double(weight.grams) * (1 + Double(reps) / 30)).rounded()))
    }
}

/// A personal record: what was beaten, and the new best.
public enum PersonalRecord: Hashable, Sendable {
    case estimate(Mass)
    case heaviest(Mass)
    case repBest(reps: Int, weight: Mass)
    /// Reps in one set without weight.
    case mostReps(Int)
    case longest(seconds: Int)
    /// Σ reps × weight in one workout.
    case volume(grams: Int)

    /// Most telling first: shown when only one record fits.
    var rank: Int {
        switch self {
        case .estimate: 0
        case .heaviest: 1
        case .repBest: 2
        case .mostReps: 3
        case .longest: 4
        case .volume: 5
        }
    }

    /// Records of the same kind (and rep count) replace each other.
    var kind: String {
        switch self {
        case .estimate: "estimate"
        case .heaviest: "heaviest"
        case .repBest(let reps, _): "reps\(reps)"
        case .mostReps: "mostReps"
        case .longest: "longest"
        case .volume: "volume"
        }
    }
}

/// An exercise's bests so far. A new result counts as a record only when it beats an earlier
/// one, so the first time doing an exercise (or a rep count) sets no records.
public struct ExerciseRecords: Equatable, Sendable {
    public private(set) var bestEstimate: Mass?
    public private(set) var heaviest: Mass?
    /// The heaviest weight lifted for each rep count from 1 to 10.
    public private(set) var bestByReps: [Int: Mass] = [:]
    /// The most reps in one set without weight.
    public private(set) var mostReps: Int?
    public private(set) var longestSeconds: Int?
    /// The biggest Σ reps × weight in one workout, in grams.
    public private(set) var bestVolumeGrams: Int?

    public init() {}

    public init(sessions: [ExerciseSession]) {
        for session in sessions { addSession(session.results) }
    }

    public var isEmpty: Bool {
        bestEstimate == nil && heaviest == nil && bestByReps.isEmpty && mostReps == nil
            && longestSeconds == nil && bestVolumeGrams == nil
    }

    /// The records `value` would break, most telling first.
    public func broken(by value: SetValue) -> [PersonalRecord] {
        var records: [PersonalRecord] = []
        switch value {
        case .reps(let reps, let weight?) where weight.grams > 0:
            if let estimate = OneRepMax.estimate(value), let best = bestEstimate, estimate > best {
                records.append(.estimate(estimate))
            }
            if let best = heaviest, weight > best {
                records.append(.heaviest(weight))
            }
            if let best = bestByReps[reps], weight > best {
                records.append(.repBest(reps: reps, weight: weight))
            }
        case .reps(let reps, _):
            if let best = mostReps, reps > best { records.append(.mostReps(reps)) }
        case .duration(let seconds):
            if let best = longestSeconds, seconds > best { records.append(.longest(seconds: seconds)) }
        }
        return records
    }

    public mutating func add(_ value: SetValue) {
        switch value {
        case .reps(let reps, let weight?) where weight.grams > 0:
            if let estimate = OneRepMax.estimate(value) { bestEstimate = max(bestEstimate ?? estimate, estimate) }
            heaviest = max(heaviest ?? weight, weight)
            if (1...OneRepMax.maxReps).contains(reps) { bestByReps[reps] = max(bestByReps[reps] ?? weight, weight) }
        case .reps(let reps, _):
            if reps > 0 { mostReps = max(mostReps ?? reps, reps) }
        case .duration(let seconds):
            longestSeconds = max(longestSeconds ?? seconds, seconds)
        }
    }

    /// Adds one workout's logged sets of the exercise, including its volume.
    public mutating func addSession(_ values: [SetValue]) {
        values.forEach { add($0) }
        let volume = values.reduce(0) { $0 + $1.volumeGrams }
        if volume > 0 { bestVolumeGrams = max(bestVolumeGrams ?? volume, volume) }
    }

    /// The records one workout's logged sets of the exercise broke, against these earlier
    /// records: each set in order, then the workout's volume. One record of each kind (the
    /// best), most telling first.
    public func broken(bySession values: [SetValue]) -> [PersonalRecord] {
        var running = self
        var found: [PersonalRecord] = []
        for value in values {
            for record in running.broken(by: value) {
                found.removeAll { $0.kind == record.kind }
                found.append(record)
            }
            running.add(value)
        }
        let volume = values.reduce(0) { $0 + $1.volumeGrams }
        if let best = bestVolumeGrams, volume > best { found.append(.volume(grams: volume)) }
        return found.sorted { $0.rank < $1.rank }
    }

    /// Which of these sets set a record when logged, in order: each against history plus the
    /// sets before it.
    public func recordSets(_ sets: [WorkoutSet]) -> Set<UUID> {
        var running = self
        var ids: Set<UUID> = []
        for set in sets where set.status.isLogged {
            if !running.broken(by: set.value).isEmpty { ids.insert(set.id) }
            running.add(set.value)
        }
        return ids
    }
}

extension ExerciseProgress {
    /// The best estimated one-rep max of each session that has one, oldest first, for a chart.
    public static func estimates(_ sessions: [ExerciseSession]) -> [(date: Date, estimate: Mass)] {
        sessions
            .compactMap { session -> (date: Date, estimate: Mass)? in
                session.results.compactMap(OneRepMax.estimate).max().map { (date: session.date, estimate: $0) }
            }
            .sorted { $0.date < $1.date }
    }
}
