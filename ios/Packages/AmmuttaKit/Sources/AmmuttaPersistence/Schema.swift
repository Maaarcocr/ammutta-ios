import Foundation
import SwiftData

// SwiftData models are storage records, not the domain model. The store maps them to
// AmmuttaCore types, so screens never see @Model classes. Nested values (plan exercises,
// workout sets, timers) are stored as one JSON blob per row: they are always read and
// written together and never queried on their own.
//
// Once a TestFlight build ships, SchemaV1 is frozen. Later changes add SchemaV2 plus a
// migration stage and a migration test. Destructive migrations are never allowed.

public enum AmmuttaSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CustomExerciseRecord.self, PlanRecord.self, WorkoutRecord.self]
    }

    @Model
    final class CustomExerciseRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var kind: String
        var createdAt: Date

        init(id: UUID, name: String, kind: String, createdAt: Date) {
            self.id = id
            self.name = name
            self.kind = kind
            self.createdAt = createdAt
        }
    }

    @Model
    final class PlanRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var updatedAt: Date
        /// JSON-encoded `Plan`.
        var payload: Data

        init(id: UUID, name: String, createdAt: Date, updatedAt: Date, payload: Data) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.payload = payload
        }
    }

    @Model
    final class WorkoutRecord {
        @Attribute(.unique) var id: UUID
        var planID: UUID?
        var startedAt: Date
        /// nil while the workout is active. At most one row may be active.
        var endedAt: Date?
        /// JSON-encoded `Workout`.
        var payload: Data

        init(id: UUID, planID: UUID?, startedAt: Date, endedAt: Date?, payload: Data) {
            self.id = id
            self.planID = planID
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.payload = payload
        }
    }
}

typealias CustomExerciseRecord = AmmuttaSchemaV1.CustomExerciseRecord
typealias PlanRecord = AmmuttaSchemaV1.PlanRecord
typealias WorkoutRecord = AmmuttaSchemaV1.WorkoutRecord

enum AmmuttaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AmmuttaSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
