import Foundation

/// Everything the app stores, as one versioned JSON file: the way to move to a new phone or
/// keep a copy without any Ammutta service (product spec §12).
public struct AmmuttaBackup: Codable, Equatable, Sendable {
    public static let formatName = "ammutta-backup"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var weightUnit: WeightUnit
    public var defaultRestSeconds: Int
    public var customExercises: [CustomExercise]
    public var plans: [Plan]
    /// Finished workouts only; an active one isn't part of a backup.
    public var workouts: [Workout]

    public init(
        exportedAt: Date, weightUnit: WeightUnit, defaultRestSeconds: Int,
        customExercises: [CustomExercise], plans: [Plan], workouts: [Workout]
    ) {
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.weightUnit = weightUnit
        self.defaultRestSeconds = defaultRestSeconds
        self.customExercises = customExercises
        self.plans = plans
        self.workouts = workouts.filter(\.isFinished)
    }

    public enum ReadError: Error, Equatable, Sendable {
        /// Not an Ammutta backup at all.
        case notABackup
        /// Made by a newer version of the app.
        case newerVersion
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads a backup file. Unfinished workouts are dropped and settings are kept in range.
    public static func decode(_ data: Data) throws(ReadError) -> AmmuttaBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { var format: String; var version: Int }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatName else {
            throw .notABackup
        }
        guard header.version <= currentVersion else { throw .newerVersion }
        guard var backup = try? decoder.decode(AmmuttaBackup.self, from: data) else { throw .notABackup }
        backup.workouts = backup.workouts.filter(\.isFinished)
        backup.defaultRestSeconds = min(max(backup.defaultRestSeconds, Limits.restSeconds.lowerBound), Limits.restSeconds.upperBound)
        return backup
    }
}
