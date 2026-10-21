import Foundation

/// Self-contained plan links that work offline and are easy to write by hand (or by an AI).
///
///     ammutta://plan?v=1&name=Push%20Day&e=barbell-bench-press:3x8@60:150&e=plank:3x45s:60
///
/// Each `e` is `<exercise>:<sets>[:<rest>]`, in plan order. The full format is documented in
/// docs/plan-links.md; keep the two in sync.
public enum PlanLink {
    public static let scheme = "ammutta"
    public static let host = "plan"
    public static let version = 1
    public static let maxLength = 8_000
    public static let maxExercises = 30

    /// A parsed link. Exercise names are resolved against the catalog and the user's custom
    /// exercises by the app, which knows the localized names.
    public struct Draft: Equatable, Sendable {
        public var name: String
        public var exercises: [Exercise]
    }

    public struct Exercise: Equatable, Sendable {
        public var reference: Reference
        public var kind: TrackingKind
        /// nil when the link leaves rest to the user's default.
        public var restSeconds: Int?
        public var sets: [SetValue]
    }

    public enum Reference: Equatable, Sendable {
        /// An exact built-in key such as `barbell-bench-press`.
        case builtIn(key: String)
        /// Any other name: matched to a built-in or custom exercise by name, or created.
        case named(String)
    }

    public enum ParseError: Error, Equatable, Sendable {
        case notAPlanLink
        case tooLong
        case unsupportedVersion
        case invalidUnit
        case missingName
        case nameTooLong
        case noExercises
        case tooManyExercises
        /// 1-based position of the exercise in the link.
        case invalidExercise(Int)
    }

    // MARK: Parsing

    /// Accepts a pasted link with surrounding whitespace, unencoded spaces and accented letters.
    public static func parse(_ text: String) throws(ParseError) -> Draft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else { throw .tooLong }
        guard let components = URLComponents(string: trimmed)
                ?? trimmed.addingPercentEncoding(withAllowedCharacters: lenientAllowed).flatMap(URLComponents.init(string:))
        else { throw .notAPlanLink }
        return try parse(components)
    }

    /// Everything already valid in a link, including existing escapes; only invalid characters get encoded.
    private static let lenientAllowed = CharacterSet.urlQueryAllowed.union(CharacterSet(charactersIn: "%#"))

    public static func parse(_ url: URL) throws(ParseError) -> Draft {
        guard url.absoluteString.count <= maxLength else { throw .tooLong }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw .notAPlanLink }
        return try parse(components)
    }

    private static func parse(_ components: URLComponents) throws(ParseError) -> Draft {
        guard components.scheme?.lowercased() == scheme, components.host?.lowercased() == host else {
            throw .notAPlanLink
        }
        let items = components.queryItems ?? []
        func values(_ key: String) -> [String] {
            items.filter { $0.name.lowercased() == key }.compactMap(\.value)
        }

        guard values("v").first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) == version else {
            throw .unsupportedVersion
        }
        let unit: WeightUnit
        switch values("unit").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case nil, "kg": unit = .kilograms
        case "lb", "lbs": unit = .pounds
        default: throw .invalidUnit
        }

        let name = (values("name").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw .missingName }
        guard name.count <= Limits.nameLength.upperBound else { throw .nameTooLong }

        let specs = values("e")
        guard !specs.isEmpty else { throw .noExercises }
        guard specs.count <= maxExercises else { throw .tooManyExercises }

        var exercises: [Exercise] = []
        for (index, spec) in specs.enumerated() {
            guard let exercise = parseExercise(spec, unit: unit) else { throw .invalidExercise(index + 1) }
            exercises.append(exercise)
        }
        return Draft(name: name, exercises: exercises)
    }

    private static func parseExercise(_ spec: String, unit: WeightUnit) -> Exercise? {
        let fields = spec.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard (2...3).contains(fields.count), !fields[0].isEmpty, !fields[1].isEmpty else { return nil }

        var sets: [SetValue] = []
        for token in fields[1].split(separator: ",", omittingEmptySubsequences: false) {
            guard let expanded = parseSetGroup(String(token), unit: unit) else { return nil }
            sets += expanded
        }
        guard Limits.setsPerExercise.contains(sets.count), let kind = sets.first?.kind,
              sets.allSatisfy({ $0.kind == kind }) else { return nil }
        for set in sets {
            do { try set.validateAsTarget() } catch { return nil }
        }

        var rest: Int?
        if fields.count == 3, !fields[2].isEmpty {
            guard let seconds = Int(fields[2]) ?? parseDuration(fields[2]),
                  Limits.restSeconds.contains(seconds) else { return nil }
            rest = seconds
        }

        let reference: Reference
        let lowered = fields[0].lowercased()
        if let builtIn = ExerciseCatalog.exercise(forKey: lowered) {
            guard builtIn.kind == kind else { return nil }
            reference = .builtIn(key: builtIn.key)
        } else {
            guard fields[0].count <= Limits.nameLength.upperBound else { return nil }
            reference = .named(fields[0])
        }
        return Exercise(reference: reference, kind: kind, restSeconds: rest, sets: sets)
    }

    /// `8`, `8@60`, `45s`, `1m30s`, or any of those prefixed with a repeat count: `3x8@60`.
    private static func parseSetGroup(_ raw: String, unit: WeightUnit) -> [SetValue]? {
        let token = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let x = token.firstIndex(of: "x"), let count = Int(token[..<x]) {
            guard Limits.setsPerExercise.contains(count),
                  let set = parseSet(String(token[token.index(after: x)...]), unit: unit) else { return nil }
            return Array(repeating: set, count: count)
        }
        return parseSet(token, unit: unit).map { [$0] }
    }

    private static func parseSet(_ token: String, unit: WeightUnit) -> SetValue? {
        if let seconds = parseDuration(token) { return .duration(seconds: seconds) }
        let parts = token.split(separator: "@", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let reps = Int(parts[0]) else { return nil }
        guard parts.count == 2 else { return .reps(count: reps, weight: nil) }
        guard let value = Double(parts[1]), value.isFinite, value >= 0 else { return nil }
        let mass = Mass(value, unit: unit)
        return .reps(count: reps, weight: mass.grams > 0 ? mass : nil)
    }

    /// `45s`, `2m`, `1m30s`. Plain numbers are not durations.
    static func parseDuration(_ token: String) -> Int? {
        let token = token.lowercased()
        guard token.hasSuffix("s") || token.hasSuffix("m") else { return nil }
        var minutes = 0, seconds = 0, digits = ""
        var sawMinutes = false, sawSeconds = false
        for character in token {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if character == "m", !sawMinutes, !sawSeconds, let value = Int(digits) {
                minutes = value; digits = ""; sawMinutes = true
            } else if character == "s", !sawSeconds, let value = Int(digits) {
                seconds = value; digits = ""; sawSeconds = true
            } else {
                return nil
            }
        }
        guard digits.isEmpty, sawMinutes || sawSeconds else { return nil }
        let total = minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    // MARK: Encoding

    /// A link for sharing `plan`. Built-ins are written as keys, custom exercises as names.
    public static func url(for plan: Plan, customNames: [ExerciseID: String], unit: WeightUnit = .kilograms) -> URL? {
        var query = ["v=\(version)", "name=\(encode(plan.name))"]
        if unit == .pounds { query.append("unit=lb") }
        for exercise in plan.exercises {
            let reference: String
            switch exercise.exercise {
            case .builtIn(let key): reference = key
            case .custom(let id):
                guard let name = customNames[id] else { return nil }
                reference = name.replacingOccurrences(of: ":", with: " ")
            }
            let spec = "\(reference):\(encodeSets(exercise.sets, unit: unit)):\(exercise.restSeconds)"
            query.append("e=\(encode(spec))")
        }
        return URL(string: "\(scheme)://\(host)?\(query.joined(separator: "&"))")
    }

    /// Readable query encoding: keeps `: , @` as they are, escapes what would break the query.
    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        return allowed
    }()

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    static func encodeSets(_ sets: [SetValue], unit: WeightUnit) -> String {
        var groups: [(SetValue, Int)] = []
        for set in sets {
            if let last = groups.last, last.0 == set {
                groups[groups.count - 1].1 += 1
            } else {
                groups.append((set, 1))
            }
        }
        return groups.map { set, count in
            let token = encodeSet(set, unit: unit)
            return count > 1 ? "\(count)x\(token)" : token
        }.joined(separator: ",")
    }

    private static func encodeSet(_ set: SetValue, unit: WeightUnit) -> String {
        switch set {
        case .reps(let count, nil):
            return "\(count)"
        case .reps(let count, let weight?):
            return "\(count)@\(number(weight.value(in: unit)))"
        case .duration(let seconds):
            return encodeDuration(seconds)
        }
    }

    static func encodeDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60, rest = seconds % 60
        if minutes == 0 { return "\(rest)s" }
        return rest == 0 ? "\(minutes)m" : "\(minutes)m\(rest)s"
    }

    /// Locale-independent, no trailing zeros: 60, 62.5, 61.25.
    private static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
