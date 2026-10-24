import Foundation

/// A workout read from another app's export, before its exercises are matched to Ammutta's.
public struct ImportedWorkout: Equatable, Sendable {
    public var title: String
    public var startedAt: Date
    public var endedAt: Date
    public var exercises: [ImportedExercise]

    public init(title: String, startedAt: Date, endedAt: Date, exercises: [ImportedExercise]) {
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exercises = exercises
    }
}

/// One exercise of an imported workout: the other app's name, how it's tracked, and its sets.
public struct ImportedExercise: Equatable, Sendable {
    public var name: String
    public var kind: TrackingKind
    public var sets: [SetValue]

    public init(name: String, kind: TrackingKind, sets: [SetValue]) {
        self.name = name
        self.kind = kind
        self.sets = sets
    }
}

/// Reads workout history exported as CSV by Strong or Hevy (product spec §12).
///
/// - Strong: `Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,…`,
///   dates like `2020-12-30 18:51:52`, durations like `1h 5m`. Plain `Weight` is in the
///   user's unit; `Weight (kg)` / `Weight (lbs)` say theirs. Some locales use `;`.
/// - Hevy: `title,start_time,end_time,…,exercise_title,…,set_type,weight_kg|weight_lbs,reps,…,duration_seconds`,
///   dates like `30 Jun 2025, 19:56`.
///
/// Times are local wall-clock times in `timeZone`. Cardio-only rows (distance, no reps or
/// time) and Strong's rest-timer rows are skipped: Ammutta doesn't track them.
public enum HistoryCSV {
    public enum ParseError: Error, Equatable, Sendable {
        case unrecognized
        case noWorkouts
    }

    public static func parse(_ text: String, unit: WeightUnit, timeZone: TimeZone) throws(ParseError) -> [ImportedWorkout] {
        let rows = CSV.rows(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces) }) else { throw .unrecognized }
        let columns = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let workouts: [ImportedWorkout]
        if columns["Workout Name"] != nil, columns["Exercise Name"] != nil, columns["Date"] != nil {
            workouts = strong(rows.dropFirst(), columns: columns, unit: unit, timeZone: timeZone)
        } else if columns["title"] != nil, columns["start_time"] != nil, columns["exercise_title"] != nil {
            workouts = hevy(rows.dropFirst(), columns: columns, timeZone: timeZone)
        } else {
            throw .unrecognized
        }
        guard !workouts.isEmpty else { throw .noWorkouts }
        return workouts
    }

    // MARK: Strong

    private static func strong(_ rows: ArraySlice<[String]>, columns: [String: Int], unit: WeightUnit, timeZone: TimeZone) -> [ImportedWorkout] {
        let weightColumn = ["Weight", "Weight (kg)", "Weight (lbs)", "Weight (lb)"].first { columns[$0] != nil }
        let weightUnit: WeightUnit = switch weightColumn ?? "" {
        case "Weight (kg)": .kilograms
        case "Weight (lbs)", "Weight (lb)": .pounds
        default: unit
        }
        let format = formatter("yyyy-MM-dd HH:mm:ss", timeZone)
        var builder = Builder()
        for row in rows {
            let field = { (name: String) in columns[name].flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            guard let start = format.date(from: field("Date")) else { continue }
            if field("Set Order").localizedCaseInsensitiveContains("rest") { continue }
            let duration = seconds(of: field("Duration"))
            let set = value(
                reps: number(field("Reps")), weight: number(weightColumn.map(field) ?? ""), unit: weightUnit,
                seconds: number(field("Seconds"))
            )
            builder.add(
                workout: field("Workout Name"), start: start, end: start.addingTimeInterval(TimeInterval(max(duration, 60))),
                exercise: field("Exercise Name"), set: set
            )
        }
        return builder.workouts
    }

    /// "1h 5m", "45m", "2h", "30s" → seconds.
    static func seconds(of duration: String) -> Int {
        var total = 0
        for token in duration.split(separator: " ") {
            guard let unit = token.last, let amount = Int(token.dropLast()) else { continue }
            switch unit {
            case "h": total += amount * 3600
            case "m": total += amount * 60
            case "s": total += amount
            default: break
            }
        }
        return total
    }

    // MARK: Hevy

    private static func hevy(_ rows: ArraySlice<[String]>, columns: [String: Int], timeZone: TimeZone) -> [ImportedWorkout] {
        let pounds = columns["weight_kg"] == nil && columns["weight_lbs"] != nil
        let format = formatter("dd MMM yyyy, HH:mm", timeZone)
        var builder = Builder()
        for row in rows {
            let field = { (name: String) in columns[name].flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespaces) ?? "" }
            guard let start = format.date(from: field("start_time")) else { continue }
            let end = format.date(from: field("end_time")).flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(60)
            let set = value(
                reps: number(field("reps")), weight: number(field(pounds ? "weight_lbs" : "weight_kg")),
                unit: pounds ? .pounds : .kilograms, seconds: number(field("duration_seconds"))
            )
            builder.add(workout: field("title"), start: start, end: end, exercise: field("exercise_title"), set: set)
        }
        return builder.workouts
    }

    // MARK: Shared

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// A reps set when there are reps, a timed set when there's only time, nothing otherwise.
    private static func value(reps: Double?, weight: Double?, unit: WeightUnit, seconds: Double?) -> SetValue? {
        if let reps, reps >= 1 {
            let count = min(Int(reps.rounded()), Limits.loggedReps.upperBound)
            let mass = weight.flatMap { $0 > 0 ? Mass($0, unit: unit) : nil }
            let clamped = mass.map { Mass(grams: min($0.grams, Limits.weightGrams.upperBound)) }
            return .reps(count: count, weight: clamped)
        }
        if let seconds, seconds >= 1 {
            return .duration(seconds: min(Int(seconds.rounded()), Limits.loggedSeconds.upperBound))
        }
        return nil
    }

    /// Groups rows into workouts (by title and start) and exercises (consecutive rows with the
    /// same name and kind, at most 20 sets each).
    private struct Builder {
        private(set) var workouts: [ImportedWorkout] = []

        mutating func add(workout title: String, start: Date, end: Date, exercise name: String, set: SetValue?) {
            guard let set, !name.isEmpty else { return }
            if workouts.last?.title != title || workouts.last?.startedAt != start {
                workouts.append(ImportedWorkout(title: title, startedAt: start, endedAt: end, exercises: []))
            }
            let w = workouts.count - 1
            if let last = workouts[w].exercises.last, last.name == name, last.kind == set.kind,
               last.sets.count < Limits.setsPerExercise.upperBound {
                workouts[w].exercises[workouts[w].exercises.count - 1].sets.append(set)
            } else {
                workouts[w].exercises.append(ImportedExercise(name: name, kind: set.kind, sets: [set]))
            }
        }
    }
}

/// Matches another app's exercise names, like "Bench Press (Dumbbell)", to built-in exercises.
public enum ImportedExerciseNames {
    /// Common Strong and Hevy names that don't follow the "Name (Equipment)" pattern.
    static let aliases: [String: String] = [
        "squat (barbell)": "barbell-back-squat",
        "front squat (barbell)": "barbell-front-squat",
        "bent over row (barbell)": "barbell-row",
        "bicep curl (barbell)": "barbell-curl",
        "bicep curl (dumbbell)": "dumbbell-curl",
        "bicep curl (cable)": "cable-curl",
        "triceps dip": "dip",
        "chest dip": "dip",
        "lateral raise (dumbbell)": "dumbbell-lateral-raise",
        "romanian deadlift (barbell)": "barbell-romanian-deadlift",
        "hip thrust (barbell)": "barbell-hip-thrust",
        "seated row (cable)": "seated-cable-row",
        "face pull (cable)": "cable-face-pull",
        "triceps pushdown (cable straight bar)": "triceps-pushdown",
        "shrug (barbell)": "barbell-shrug",
        "goblet squat (kettlebell)": "kettlebell-goblet-squat",
        "pull up (assisted)": "assisted-pull-up",
    ]

    /// The built-in exercise key for `name`, or nil. `englishName` gives each built-in's English name.
    public static func builtInKey(for name: String, kind: TrackingKind, englishName: (String) -> String) -> String? {
        let candidates = ExerciseCatalog.all.filter { $0.kind == kind }
        let names = candidates.map { (exercise: $0, name: loosened(englishName($0.key))) }
        let loose = loosened(name)
        if let alias = aliases[loose], candidates.contains(where: { $0.key == alias }) { return alias }
        func named(_ text: String, equipment: Equipment? = nil) -> String? {
            names.first { $0.name == text && (equipment == nil || $0.exercise.equipment == equipment) }?.exercise.key
        }
        if let exact = named(loose) { return exact }
        // "Base (Equipment)": "Equipment Base", then the base name with that equipment.
        guard let open = name.lastIndex(of: "("), name.hasSuffix(")") else { return nil }
        let base = loosened(String(name[..<open]))
        let label = loosened(String(name[name.index(after: open)..<name.index(before: name.endIndex)]))
        guard let equipment = Equipment(rawValue: label) else { return nil }
        return named("\(label) \(base)") ?? named(base, equipment: equipment)
    }

    /// Lowercased, without accents or punctuation like hyphens, single spaces.
    static func loosened(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let spaced = folded.map { $0.isLetter || $0.isNumber || $0 == "(" || $0 == ")" ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}

/// A small CSV reader: quoted fields (with "" for a quote and line breaks inside quotes),
/// `,` or `;` as separator (picked from the header line), and an optional byte-order mark.
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var text = Substring(text)
        if text.first == "\u{FEFF}" { text = text.dropFirst() }
        let headerLine = text.prefix { !$0.isNewline }
        let separator: Character = headerLine.filter { $0 == ";" }.count > headerLine.filter { $0 == "," }.count ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil
        while let character = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if character == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character.isNewline {
                row.append(field)
                field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }
}
