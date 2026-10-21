import Foundation

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case bodyweight, barbell, dumbbell, kettlebell, cable, machine, other
}

public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case chest, back, shoulders, arms, legs, glutes, core, fullBody
}

/// What plans and logs point at. Built-in names are localized at display time.
public enum ExerciseRef: Hashable, Codable, Sendable {
    case builtIn(key: String)
    case custom(ExerciseID)
}

public struct BuiltInExercise: Hashable, Sendable, Identifiable {
    public let key: String
    public let kind: TrackingKind
    public let equipment: Equipment
    public let muscle: MuscleGroup

    public var id: String { key }
    public var ref: ExerciseRef { .builtIn(key: key) }

    public init(_ key: String, _ kind: TrackingKind, _ equipment: Equipment, _ muscle: MuscleGroup) {
        self.key = key
        self.kind = kind
        self.equipment = equipment
        self.muscle = muscle
    }
}

public struct CustomExercise: Hashable, Codable, Sendable, Identifiable {
    public var id: ExerciseID
    public var name: String
    public var kind: TrackingKind
    public var createdAt: Date

    public init(id: ExerciseID = ExerciseID(), name: String, kind: TrackingKind, createdAt: Date) {
        self.id = id
        self.name = name
        self.kind = kind
        self.createdAt = createdAt
    }

    public var ref: ExerciseRef { .custom(id) }

    public func validate() throws(ValidationError) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyName }
        guard trimmed.count <= Limits.nameLength.upperBound else { throw .nameTooLong }
    }
}

public enum ExerciseNames {
    /// Case-, diacritic- and surrounding-whitespace-insensitive form used for duplicate checks.
    public static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    public static func isDuplicate(_ name: String, among existing: [String]) -> Bool {
        let candidate = normalized(name)
        guard !candidate.isEmpty else { return false }
        return existing.contains { normalized($0) == candidate }
    }
}
