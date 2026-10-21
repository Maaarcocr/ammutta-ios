import Foundation

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case kilograms = "kg"
    case pounds = "lb"

    /// The +/- step used by workout controls.
    public var increment: Double {
        switch self {
        case .kilograms: 2.5
        case .pounds: 5
        }
    }
}

/// A weight stored as integer grams, so repeated edits never drift.
/// Input is rounded to 0.25 of the display unit.
public struct Mass: Hashable, Codable, Sendable, Comparable {
    public var grams: Int

    public init(grams: Int) { self.grams = grams }

    public static let gramsPerPound = 453.59237
    public static let zero = Mass(grams: 0)

    public static func kilograms(_ value: Double) -> Mass {
        let quarter = (value * 4).rounded() / 4
        return Mass(grams: Int((quarter * 1000).rounded()))
    }

    public static func pounds(_ value: Double) -> Mass {
        let quarter = (value * 4).rounded() / 4
        return Mass(grams: Int((quarter * gramsPerPound).rounded()))
    }

    public init(_ value: Double, unit: WeightUnit) {
        switch unit {
        case .kilograms: self = .kilograms(value)
        case .pounds: self = .pounds(value)
        }
    }

    /// The value in `unit`, rounded to 0.25 of that unit.
    public func value(in unit: WeightUnit) -> Double {
        let raw: Double
        switch unit {
        case .kilograms: raw = Double(grams) / 1000
        case .pounds: raw = Double(grams) / Self.gramsPerPound
        }
        return (raw * 4).rounded() / 4
    }

    /// Adds `delta` display units and clamps to the allowed range.
    public func adding(_ delta: Double, unit: WeightUnit) -> Mass {
        let next = Mass(max(0, value(in: unit) + delta), unit: unit)
        return Mass(grams: min(next.grams, Limits.weightGrams.upperBound))
    }

    public static func < (lhs: Mass, rhs: Mass) -> Bool { lhs.grams < rhs.grams }
}
