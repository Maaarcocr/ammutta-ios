import Foundation
import Testing
@testable import AmmuttaCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

struct HeartRateMeasurementTests {
    @Test func readsEightBitValues() {
        #expect(HeartRateMeasurement.bpm(from: [0x00, 72]) == 72)
        #expect(HeartRateMeasurement.bpm(from: [0x00, 250]) == 250)
    }

    @Test func readsSixteenBitLittleEndianValues() {
        #expect(HeartRateMeasurement.bpm(from: [0x01, 0xB4, 0x00]) == 180)
        #expect(HeartRateMeasurement.bpm(from: [0x01, 0x48, 0x00, 0xFF]) == 72)
    }

    @Test func ignoresEnergyAndRRIntervalFields() {
        // Energy expended (bit 3) and two RR intervals (bit 4) after the value.
        #expect(HeartRateMeasurement.bpm(from: [0x18, 75, 0x10, 0x00, 0x00, 0x04, 0x10, 0x04]) == 75)
        #expect(HeartRateMeasurement.bpm(from: [0x11, 0x5A, 0x00, 0x00, 0x04]) == 90)
    }

    @Test func respectsSensorContact() {
        #expect(HeartRateMeasurement.bpm(from: [0x06, 80]) == 80)   // supported, detected
        #expect(HeartRateMeasurement.bpm(from: [0x04, 80]) == nil)  // supported, not detected
        #expect(HeartRateMeasurement.bpm(from: [0x02, 80]) == 80)   // not supported
    }

    @Test func rejectsImplausibleAndMalformedData() {
        #expect(HeartRateMeasurement.bpm(from: []) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x00]) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x01, 0x50]) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x00, 0]) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x00, 251]) == nil)
        #expect(HeartRateMeasurement.bpm(from: [0x01, 0x2C, 0x01]) == nil) // 300
    }
}

struct WorkoutHeartRateTests {
    private func workout() -> Workout {
        Workout(planID: nil, planName: "Legs", startedAt: t0, exercises: [])
    }

    @Test func keepsOneReadingEveryFiveSeconds() {
        var workout = workout()
        #expect(workout.recordHeartRate(120, at: t0.addingTimeInterval(1)))
        #expect(!workout.recordHeartRate(125, at: t0.addingTimeInterval(4)))
        #expect(workout.recordHeartRate(150, at: t0.addingTimeInterval(6)))
        #expect(workout.heartRate.map(\.bpm) == [120, 150])
    }

    @Test func ignoresReadingsOutsideTheWorkout() {
        var workout = workout()
        #expect(!workout.recordHeartRate(120, at: t0.addingTimeInterval(-10)))
        #expect(!workout.recordHeartRate(0, at: t0.addingTimeInterval(10)))
        workout.endedAt = t0.addingTimeInterval(60)
        #expect(!workout.recordHeartRate(120, at: t0.addingTimeInterval(30)))
        #expect(workout.heartRate.isEmpty)
    }

    @Test func summaryHasAverageAndMaximum() {
        var workout = workout()
        workout.recordHeartRate(120, at: t0.addingTimeInterval(5))
        workout.recordHeartRate(151, at: t0.addingTimeInterval(10))
        let summary = WorkoutSummary(workout, now: t0.addingTimeInterval(60))
        #expect(summary.averageHeartRate == 136)
        #expect(summary.maxHeartRate == 151)
        #expect(WorkoutSummary(self.workout(), now: t0).averageHeartRate == nil)
    }

    @Test func roundTripsAndReadsWorkoutsSavedBeforeHeartRate() throws {
        var workout = workout()
        workout.recordHeartRate(130, at: t0.addingTimeInterval(5))
        let data = try JSONEncoder().encode(workout)
        #expect(try JSONDecoder().decode(Workout.self, from: data) == workout)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "heartRate")
        let old = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Workout.self, from: old)
        #expect(decoded.heartRate.isEmpty)
        #expect(decoded.id == workout.id)
    }
}
