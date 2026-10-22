import AmmuttaCore
import Foundation
@preconcurrency import HealthKit
import Observation
import os

private let logger = Logger(subsystem: "dev.ammutta.app", category: "HealthSync")

/// Writes workouts to Apple Health. Both calls are idempotent: everything Ammutta writes
/// carries the workout ID as `HKMetadataKeyExternalUUID`.
@MainActor
protocol HealthSyncing: AnyObject {
    var isAvailable: Bool { get }
    /// True when the user allowed Ammutta to save workouts.
    var isAuthorized: Bool { get }
    func requestAuthorization() async
    func save(_ workout: Workout) async throws
    func delete(_ id: WorkoutID) async throws
}

@MainActor
final class HealthKitSync: HealthSyncing {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isAuthorized: Bool {
        isAvailable && store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: [.workoutType(), HKQuantityType(.heartRate)], read: [])
        } catch {
            logger.error("Health authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    func save(_ workout: Workout) async throws {
        try await Self.save(workout, to: store)
    }

    func delete(_ id: WorkoutID) async throws {
        try await Self.delete(id, from: store)
    }

    private nonisolated static func ownedBy(_ id: WorkoutID) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id.rawValue.uuidString])
    }

    @concurrent
    private nonisolated static func save(_ workout: Workout, to store: HKHealthStore) async throws {
        guard let end = workout.endedAt else { return }
        let id = workout.id.rawValue.uuidString
        let existing = HKSampleQueryDescriptor(predicates: [.workout(ownedBy(workout.id))], sortDescriptors: [], limit: 1)
        guard try await existing.result(for: store).isEmpty else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: workout.startedAt)
        let heartRate = HKQuantityType(.heartRate)
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let samples = workout.heartRate.map { sample in
            HKQuantitySample(
                type: heartRate,
                quantity: HKQuantity(unit: beatsPerMinute, doubleValue: Double(sample.bpm)),
                start: sample.date,
                end: sample.date,
                metadata: [HKMetadataKeyExternalUUID: id]
            )
        }
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: id])
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }

    @concurrent
    private nonisolated static func delete(_ id: WorkoutID, from store: HKHealthStore) async throws {
        _ = try await store.deleteObjects(of: .workoutType(), predicate: ownedBy(id))
        _ = try await store.deleteObjects(of: HKQuantityType(.heartRate), predicate: ownedBy(id))
    }
}

/// Health for tests and UI tests: records calls, never touches HealthKit.
@MainActor
final class FakeHealthSync: HealthSyncing {
    var isAvailable = true
    var isAuthorized = false
    /// Every call fails while true, like Health being unavailable.
    var failing = false
    private(set) var saved: [WorkoutID] = []
    private(set) var deleted: [WorkoutID] = []

    struct Failure: Error {}

    func requestAuthorization() async { isAuthorized = true }

    func save(_ workout: Workout) async throws {
        if failing { throw Failure() }
        if !saved.contains(workout.id) { saved.append(workout.id) }
    }

    func delete(_ id: WorkoutID) async throws {
        if failing { throw Failure() }
        saved.removeAll { $0 == id }
        deleted.append(id)
    }
}

/// The "Sync to Apple Health" setting and its durable queue. Finished and deleted workouts
/// are queued while the setting is on; the queue runs in order and stops at the first
/// failure, to be retried on the next launch, return to the app or workout.
@Observable
final class HealthSync {
    @ObservationIgnored let service: any HealthSyncing
    @ObservationIgnored private let defaults: UserDefaults
    /// Finds a finished workout by ID; set by the app model.
    @ObservationIgnored var lookup: (WorkoutID) -> Workout? = { _ in nil }
    @ObservationIgnored private var running: Task<Void, Never>?
    private(set) var queue: HealthSyncQueue
    /// Mirrors the service so the settings screen updates after the permission sheet.
    private(set) var isAuthorized: Bool

    private enum Keys {
        static let enabled = "healthSyncEnabled"
        static let queue = "healthSyncQueue"
    }

    init(service: any HealthSyncing, defaults: UserDefaults) {
        self.service = service
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        queue = defaults.data(forKey: Keys.queue).flatMap { try? JSONDecoder().decode(HealthSyncQueue.self, from: $0) } ?? HealthSyncQueue()
        isAuthorized = service.isAuthorized
    }

    var isAvailable: Bool { service.isAvailable }

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                Task { await authorizeAndRun() }
            }
        }
    }

    func workoutFinished(_ id: WorkoutID) {
        guard isEnabled else { return }
        update { $0.enqueue(.save(id)) }
        run()
    }

    func workoutDeleted(_ id: WorkoutID) {
        guard isEnabled else { return }
        update { $0.enqueue(.delete(id)) }
        run()
    }

    /// Lets tests wait for the queue to drain or stop.
    func settled() async {
        await running?.value
    }

    func authorizeAndRun() async {
        if !service.isAuthorized {
            await service.requestAuthorization()
        }
        isAuthorized = service.isAuthorized
        run()
    }

    /// Runs pending jobs one at a time. Calling it while it runs does nothing.
    func run() {
        isAuthorized = service.isAuthorized
        guard running == nil, isEnabled, isAuthorized, !queue.jobs.isEmpty else { return }
        running = Task { [weak self] in
            await self?.drain()
            self?.running = nil
        }
    }

    private func drain() async {
        while isEnabled, let job = queue.next {
            do {
                switch job {
                case .save(let id):
                    // A workout deleted meanwhile has a delete job queued instead.
                    if let finished = lookup(id), finished.isFinished {
                        try await service.save(finished)
                    }
                case .delete(let id):
                    try await service.delete(id)
                }
                update { $0.complete(job) }
            } catch {
                logger.error("Health sync paused: \(String(describing: error), privacy: .public)")
                return
            }
        }
    }

    private func update(_ change: (inout HealthSyncQueue) -> Void) {
        change(&queue)
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: Keys.queue)
        }
    }
}
