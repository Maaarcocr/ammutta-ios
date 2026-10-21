import Foundation

public enum TrackingKind: String, Codable, Sendable, CaseIterable {
    case reps
    case duration
}

/// What one set is: reps with optional weight, or a duration.
/// Used both for plan targets and for what was actually done.
public enum SetValue: Hashable, Codable, Sendable {
    case reps(count: Int, weight: Mass?)
    case duration(seconds: Int)

    public var kind: TrackingKind {
        switch self {
        case .reps: .reps
        case .duration: .duration
        }
    }

    public static func defaultValue(for kind: TrackingKind) -> SetValue {
        switch kind {
        case .reps: .reps(count: 8, weight: nil)
        case .duration: .duration(seconds: 30)
        }
    }

    public var reps: Int? {
        if case .reps(let count, _) = self { return count }
        return nil
    }

    public var weight: Mass? {
        if case .reps(_, let weight) = self { return weight }
        return nil
    }

    public var seconds: Int? {
        if case .duration(let seconds) = self { return seconds }
        return nil
    }

    /// Reps × grams; zero for duration sets and sets without weight.
    public var volumeGrams: Int {
        if case .reps(let count, let weight?) = self { return count * weight.grams }
        return 0
    }

    public func withReps(_ count: Int) -> SetValue {
        guard case .reps(_, let weight) = self else { return self }
        return .reps(count: min(max(count, Limits.reps.lowerBound), Limits.reps.upperBound), weight: weight)
    }

    public func withWeight(_ weight: Mass?) -> SetValue {
        guard case .reps(let count, _) = self else { return self }
        guard let weight, weight.grams > 0 else { return .reps(count: count, weight: nil) }
        return .reps(count: count, weight: Mass(grams: min(weight.grams, Limits.weightGrams.upperBound)))
    }

    public func withSeconds(_ seconds: Int, range: ClosedRange<Int> = Limits.targetSeconds) -> SetValue {
        guard case .duration = self else { return self }
        return .duration(seconds: min(max(seconds, range.lowerBound), range.upperBound))
    }

    /// Plan targets must be inside the ranges from the product spec.
    public func validateAsTarget() throws(ValidationError) {
        switch self {
        case .reps(let count, let weight):
            guard Limits.reps.contains(count) else { throw .reps }
            if let weight, !Limits.weightGrams.contains(weight.grams) { throw .weight }
        case .duration(let seconds):
            guard Limits.targetSeconds.contains(seconds) else { throw .duration }
        }
    }

    /// Logged results are a little looser: a failed set can have 0 reps and a stopped timer can be short.
    public func validateAsResult() throws(ValidationError) {
        switch self {
        case .reps(let count, let weight):
            guard Limits.loggedReps.contains(count) else { throw .reps }
            if let weight, !Limits.weightGrams.contains(weight.grams) { throw .weight }
        case .duration(let seconds):
            guard Limits.loggedSeconds.contains(seconds) else { throw .duration }
        }
    }
}

public enum Limits {
    public static let nameLength = 1...80
    public static let setsPerExercise = 1...20
    public static let reps = 1...999
    public static let loggedReps = 0...999
    public static let weightGrams = 0...999_750
    public static let targetSeconds = 5...3600
    public static let loggedSeconds = 1...3600
    public static let restSeconds = 0...600
}

public enum ValidationError: Error, Equatable, Sendable {
    case emptyName
    case nameTooLong
    case noExercises
    case setCount
    case reps
    case weight
    case duration
    case rest
    case kindMismatch
}
