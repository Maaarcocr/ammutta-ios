import Foundation
import Testing
@testable import AmmuttaCore

struct HealthSyncQueueTests {
    @Test func runsJobsOldestFirstUntilTheySucceed() {
        let first = WorkoutID(), second = WorkoutID()
        var queue = HealthSyncQueue()
        queue.enqueue(.save(first))
        queue.enqueue(.save(second))
        #expect(queue.next == .save(first))

        queue.complete(.save(first))
        #expect(queue.next == .save(second))
        queue.complete(.save(second))
        #expect(queue.next == nil)
    }

    @Test func savingTwiceKeepsOneJob() {
        let id = WorkoutID()
        var queue = HealthSyncQueue()
        queue.enqueue(.save(id))
        queue.enqueue(.save(id))
        #expect(queue.jobs == [.save(id)])
    }

    @Test func deletingReplacesAPendingSave() {
        let id = WorkoutID(), other = WorkoutID()
        var queue = HealthSyncQueue()
        queue.enqueue(.save(id))
        queue.enqueue(.save(other))
        queue.enqueue(.delete(id))
        #expect(queue.jobs == [.save(other), .delete(id)])
        // A save after the delete is ignored: the workout is gone.
        queue.enqueue(.save(id))
        #expect(queue.jobs == [.save(other), .delete(id)])
    }

    @Test func replacingDeletesThenSavesAgain() {
        let id = WorkoutID()
        let other = WorkoutID()
        var queue = HealthSyncQueue()
        queue.enqueue(.save(id))
        queue.enqueue(.save(other))
        queue.enqueueReplacement(of: id)
        #expect(queue.jobs == [.save(other), .delete(id), .save(id)])
        queue.enqueueReplacement(of: id)
        #expect(queue.jobs == [.save(other), .delete(id), .save(id)], "replacing twice keeps one pair")
    }

    @Test func survivesEncoding() throws {
        var queue = HealthSyncQueue()
        queue.enqueue(.save(WorkoutID()))
        queue.enqueue(.delete(WorkoutID()))
        let data = try JSONEncoder().encode(queue)
        #expect(try JSONDecoder().decode(HealthSyncQueue.self, from: data) == queue)
    }
}
