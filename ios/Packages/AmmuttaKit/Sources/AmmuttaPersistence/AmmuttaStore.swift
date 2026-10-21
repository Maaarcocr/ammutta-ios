import AmmuttaCore
import Foundation
import SwiftData

public enum StoreError: Error, Equatable, Sendable {
    /// Another workout is already active; only one may exist at a time.
    case anotherWorkoutActive
}

/// All reads and writes of user data. Runs on the main actor: the data is small and
/// every write is a single short transaction.
@MainActor
public final class AmmuttaStore {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: AmmuttaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, migrationPlan: AmmuttaMigrationPlan.self, configurations: [configuration])
    }

    // MARK: Custom exercises

    public func customExercises() throws -> [CustomExercise] {
        let records = try context.fetch(FetchDescriptor<CustomExerciseRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        return records.compactMap { record in
            guard let kind = TrackingKind(rawValue: record.kind) else { return nil }
            return CustomExercise(id: ExerciseID(record.id), name: record.name, kind: kind, createdAt: record.createdAt)
        }
    }

    public func save(_ exercise: CustomExercise) throws {
        let id = exercise.id.rawValue
        if let record = try first(#Predicate<CustomExerciseRecord> { $0.id == id }) {
            record.name = exercise.name
            record.kind = exercise.kind.rawValue
        } else {
            context.insert(CustomExerciseRecord(id: id, name: exercise.name, kind: exercise.kind.rawValue, createdAt: exercise.createdAt))
        }
        try context.save()
    }

    public func deleteCustomExercise(_ exerciseID: ExerciseID) throws {
        let id = exerciseID.rawValue
        try context.delete(model: CustomExerciseRecord.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    // MARK: Plans

    public func plans() throws -> [Plan] {
        let records = try context.fetch(FetchDescriptor<PlanRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        return try records.map { try decoder.decode(Plan.self, from: $0.payload) }
    }

    public func save(_ plan: Plan) throws {
        let id = plan.id.rawValue
        let payload = try encoder.encode(plan)
        if let record = try first(#Predicate<PlanRecord> { $0.id == id }) {
            record.name = plan.name
            record.updatedAt = plan.updatedAt
            record.payload = payload
        } else {
            context.insert(PlanRecord(id: id, name: plan.name, createdAt: plan.createdAt, updatedAt: plan.updatedAt, payload: payload))
        }
        try context.save()
    }

    /// Deleting a plan never touches history: workouts carry their own copy of the plan.
    public func deletePlan(_ planID: PlanID) throws {
        let id = planID.rawValue
        try context.delete(model: PlanRecord.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    // MARK: Workouts

    public func activeWorkout() throws -> Workout? {
        guard let record = try first(#Predicate<WorkoutRecord> { $0.endedAt == nil }) else { return nil }
        return try decoder.decode(Workout.self, from: record.payload)
    }

    /// Completed workouts, newest first.
    public func completedWorkouts() throws -> [Workout] {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { try decoder.decode(Workout.self, from: $0.payload) }
    }

    /// Saves after every workout event, so an active workout survives the app being killed.
    public func save(_ workout: Workout) throws {
        let id = workout.id.rawValue
        if workout.endedAt == nil, let active = try first(#Predicate<WorkoutRecord> { $0.endedAt == nil }), active.id != id {
            throw StoreError.anotherWorkoutActive
        }
        let payload = try encoder.encode(workout)
        if let record = try first(#Predicate<WorkoutRecord> { $0.id == id }) {
            record.endedAt = workout.endedAt
            record.startedAt = workout.startedAt
            record.payload = payload
        } else {
            context.insert(WorkoutRecord(id: id, planID: workout.planID?.rawValue, startedAt: workout.startedAt, endedAt: workout.endedAt, payload: payload))
        }
        try context.save()
    }

    public func deleteWorkout(_ workoutID: WorkoutID) throws {
        let id = workoutID.rawValue
        try context.delete(model: WorkoutRecord.self, where: #Predicate { $0.id == id })
        try context.save()
    }

    // MARK: Helpers

    private func first<T: PersistentModel>(_ predicate: Predicate<T>) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
