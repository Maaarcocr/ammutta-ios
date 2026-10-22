import Foundation

/// One heart-rate reading stored with a workout.
public struct HeartRateSample: Hashable, Codable, Sendable {
    public var date: Date
    public var bpm: Int

    public init(date: Date, bpm: Int) {
        self.date = date
        self.bpm = bpm
    }
}

/// Parses the standard Bluetooth Heart Rate Measurement characteristic (`0x2A37`).
public enum HeartRateMeasurement {
    public static let plausibleBPM = 1...250

    /// Beats per minute, or nil when the data is malformed, the value is implausible,
    /// or the sensor says it has no skin contact.
    ///
    /// Flags (first byte): bit 0 picks an 8- or 16-bit value; bits 1–2 are the contact status;
    /// bits 3–4 announce energy expended and RR intervals, which follow the value and are ignored.
    public static func bpm(from bytes: [UInt8]) -> Int? {
        guard let flags = bytes.first else { return nil }
        let value: Int
        if flags & 0x01 == 0 {
            guard bytes.count >= 2 else { return nil }
            value = Int(bytes[1])
        } else {
            guard bytes.count >= 3 else { return nil }
            value = Int(bytes[1]) | Int(bytes[2]) << 8
        }
        // Contact supported (bit 2) but not detected (bit 1).
        if flags & 0b110 == 0b100 { return nil }
        return plausibleBPM.contains(value) ? value : nil
    }
}

extension Workout {
    /// One stored reading every 5 seconds is plenty for the average, maximum and chart.
    public static let heartRateInterval: TimeInterval = 5

    /// Adds a reading to an active workout. Returns false when it was not stored: the workout
    /// is finished, or the previous reading is too recent.
    @discardableResult
    public mutating func recordHeartRate(_ bpm: Int, at date: Date) -> Bool {
        guard !isFinished, date >= startedAt, HeartRateMeasurement.plausibleBPM.contains(bpm) else { return false }
        if let last = heartRate.last, date.timeIntervalSince(last.date) < Self.heartRateInterval { return false }
        heartRate.append(HeartRateSample(date: date, bpm: bpm))
        return true
    }
}
