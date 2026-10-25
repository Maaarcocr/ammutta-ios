import AmmuttaCore
import Foundation

/// Locale-aware formatting. Numbers, durations and weights always go through FormatStyle,
/// never manual string building, so Italian gets "62,5 kg" and English "62.5 kg".
enum Format {
    static func mass(_ mass: Mass, unit: WeightUnit, locale: Locale = .autoupdatingCurrent) -> String {
        let measurement = Measurement(value: mass.value(in: unit), unit: unit == .kilograms ? UnitMass.kilograms : UnitMass.pounds)
        let style = Measurement<UnitMass>.FormatStyle(
            width: .abbreviated,
            locale: locale,
            usage: .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0...2))
        )
        return measurement.formatted(style)
    }

    /// A plain number in the display unit, for steppers and text fields ("62,5").
    static func number(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// A countdown or set duration: "0:45", "12:30", "1:02:03".
    static func clock(_ seconds: Int) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds).formatted(.time(pattern: pattern))
    }

    /// A workout length: "1 hr, 5 min" / "1 h e 5 min".
    static func workoutDuration(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let rounded = max(60, (seconds / 60) * 60)
        return Duration.seconds(rounded).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)
        )
    }

    static func value(_ value: SetValue, unit: WeightUnit) -> String {
        switch value {
        case .reps(let count, nil): L10n.repsCount(count)
        case .reps(let count, let weight?): L10n.repsWeight(count, mass(weight, unit: unit))
        case .duration(let seconds): clock(seconds)
        }
    }

    /// A record's name and its value, for example "Estimated 1RM" and "82.5 kg".
    static func record(_ record: PersonalRecord, unit: WeightUnit) -> (title: String, value: String) {
        switch record {
        case .estimate(let weight): (L10n.recordsEstimate, mass(weight, unit: unit))
        case .heaviest(let weight): (L10n.recordsHeaviest, mass(weight, unit: unit))
        case .repBest(let reps, let weight): (L10n.recordsRepBest, value(.reps(count: reps, weight: weight), unit: unit))
        case .mostReps(let reps): (L10n.recordsMostReps, L10n.repsCount(reps))
        case .longest(let seconds): (L10n.recordsLongest, clock(seconds))
        case .volume(let grams): (L10n.recordsVolume, mass(Mass(grams: grams), unit: unit))
        }
    }

    /// "3 sets · 8 × 60 kg" when every set is the same, otherwise each set in order.
    static func setsSummary(_ sets: [SetValue], unit: WeightUnit) -> String {
        guard let first = sets.first else { return "" }
        if sets.allSatisfy({ $0 == first }) {
            return [L10n.setsCount(sets.count), value(first, unit: unit)].joined(separator: " · ")
        }
        return sets.map { value($0, unit: unit) }.joined(separator: " / ")
    }
}

/// Display names for built-in exercises, equipment and muscle groups (Exercises.xcstrings).
enum ExerciseText {
    static func name(_ key: String) -> String { lookup("exercise." + key) }

    /// The English name regardless of the device language, so plan links written in English
    /// (for example by an AI) still match built-in exercises on an Italian phone.
    static func englishName(_ key: String) -> String {
        (englishBundle ?? .main).localizedString(forKey: "exercise." + key, value: nil, table: "Exercises")
    }

    private static let englishBundle: Bundle? =
        Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
    static func tip(_ key: String) -> String { lookup("tip." + key) }
    static func muscles(_ key: String) -> String { lookup("muscles." + key) }
    static func equipment(_ equipment: Equipment) -> String { lookup("equipment." + equipment.rawValue) }
    static func muscle(_ muscle: MuscleGroup) -> String { lookup("muscle." + muscle.rawValue) }

    private static func lookup(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: "Exercises")
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
