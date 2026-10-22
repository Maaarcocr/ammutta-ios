import Foundation

/// One pending change to Apple Health.
public enum HealthSyncJob: Hashable, Codable, Sendable {
    /// Write a finished workout (skipped if Health already has it).
    case save(WorkoutID)
    /// Remove a workout and its heart-rate samples that Ammutta wrote.
    case delete(WorkoutID)

    public var workoutID: WorkoutID {
        switch self {
        case .save(let id), .delete(let id): id
        }
    }
}

/// The durable outbox for Apple Health: jobs run oldest first and leave the queue only once
/// they succeed. Both jobs are idempotent, so retrying after a failure or a crash is safe.
public struct HealthSyncQueue: Hashable, Codable, Sendable {
    public private(set) var jobs: [HealthSyncJob] = []

    public init(jobs: [HealthSyncJob] = []) {
        self.jobs = jobs
    }

    public var next: HealthSyncJob? { jobs.first }

    /// Adds a job. A workout has at most one pending job: deleting replaces a pending save,
    /// and saving again is a no-op.
    public mutating func enqueue(_ job: HealthSyncJob) {
        switch job {
        case .save:
            guard !jobs.contains(where: { $0.workoutID == job.workoutID }) else { return }
            jobs.append(job)
        case .delete(let id):
            jobs.removeAll { $0.workoutID == id }
            jobs.append(job)
        }
    }

    /// Removes a job once it succeeded.
    public mutating func complete(_ job: HealthSyncJob) {
        if let index = jobs.firstIndex(of: job) {
            jobs.remove(at: index)
        }
    }
}
