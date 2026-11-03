import Foundation

/// The checked-in, reviewed Jefit name → exercise table
/// (`Resources/jefit_exercise_map.json`, #166).
struct JefitExerciseMapTable: Decodable, Sendable, Equatable {
    let version: Int
    /// Jefit name → bundled catalog `externalId`.
    let catalog: [String: String]
    /// Jefit name → custom exercise name. Several Jefit spellings of one
    /// movement share a name so their history lands on one exercise.
    let custom: [String: String]

    static let resourceName = "jefit_exercise_map"

    static func bundled(_ bundle: Bundle = .main) throws -> JefitExerciseMapTable {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw JefitImportError.mappingTableMissing
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

/// An exercise already on the phone, reduced to what mapping needs.
struct JefitLocalExercise: Sendable, Equatable {
    let id: UUID
    let name: String
    let externalId: String?
    let isCustom: Bool
}

extension JefitLocalExercise {
    init(_ exercise: Exercise) {
        self.init(id: exercise.id, name: exercise.name, externalId: exercise.externalId, isCustom: exercise.isCustom)
    }
}

enum JefitExerciseTarget: Sendable, Equatable {
    /// History attaches to this exercise (catalog or an existing custom one).
    case existing(JefitLocalExercise)
    /// The import creates a custom exercise with this name.
    case newCustom(name: String)

    var name: String {
        switch self {
        case .existing(let exercise): return exercise.name
        case .newCustom(let name): return name
        }
    }

    /// True for a catalog (bundled) exercise; false for any custom one.
    var isCatalog: Bool {
        if case .existing(let exercise) = self { return !exercise.isCustom }
        return false
    }
}

enum JefitMappingMethod: String, Sendable, Equatable {
    /// The Jefit name is an exercise's name on the phone.
    case exact
    /// The reviewed table decided.
    case table
    /// Same words after normalising case, punctuation, plurals and order.
    case normalized
    /// Nothing matched: a new custom exercise under the Jefit name.
    case unmapped
}

struct JefitNameResolutionResult: Sendable, Equatable {
    let target: JefitExerciseTarget
    let method: JefitMappingMethod
}

/// Resolves a Jefit `ename` to the exercise its history should attach to.
///
/// Order: exact name → reviewed table → normalised name → new custom. The
/// table sits above the normalised guess so a reviewed "this is a different
/// movement" can veto a heuristic match; an exact name is identity and needs
/// no review. A wrong catalog match corrupts history and PRs, so the
/// normalised tier only accepts a single unambiguous candidate, and anything
/// left over becomes a custom exercise — never a silent drop.
struct JefitExerciseMapper: Sendable {
    private let tableCatalog: [String: String]
    private let tableCustom: [String: String]
    private let byLowerName: [String: [JefitLocalExercise]]
    private let byExternalId: [String: JefitLocalExercise]
    private let byNormalizedKey: [String: [JefitLocalExercise]]

    init(table: JefitExerciseMapTable, localExercises: [JefitLocalExercise]) {
        tableCatalog = Dictionary(
            table.catalog.map { (Self.clean($0.key).lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        tableCustom = Dictionary(
            table.custom.map { (Self.clean($0.key).lowercased(), Self.clean($0.value)) },
            uniquingKeysWith: { first, _ in first }
        )
        // Stable order so "first" is deterministic when names repeat.
        let ordered = localExercises.sorted {
            ($0.isCustom ? 1 : 0, $0.externalId ?? "", $0.id.uuidString)
                < ($1.isCustom ? 1 : 0, $1.externalId ?? "", $1.id.uuidString)
        }
        byLowerName = Dictionary(grouping: ordered) { Self.clean($0.name).lowercased() }
        byNormalizedKey = Dictionary(grouping: ordered) { Self.normalizedKey($0.name) }
        var byExternalId: [String: JefitLocalExercise] = [:]
        for exercise in ordered {
            if let externalId = exercise.externalId, byExternalId[externalId] == nil {
                byExternalId[externalId] = exercise
            }
        }
        self.byExternalId = byExternalId
    }

    func resolve(_ jefitName: String) -> JefitNameResolutionResult {
        let name = Self.clean(jefitName)
        let lower = name.lowercased()

        if let match = byLowerName[lower]?.first {
            return JefitNameResolutionResult(target: .existing(match), method: .exact)
        }

        if let externalId = tableCatalog[lower], let match = byExternalId[externalId] {
            return JefitNameResolutionResult(target: .existing(match), method: .table)
        }
        if let customName = tableCustom[lower] {
            if let match = byLowerName[customName.lowercased()]?.first {
                return JefitNameResolutionResult(target: .existing(match), method: .table)
            }
            return JefitNameResolutionResult(target: .newCustom(name: customName), method: .table)
        }

        if let match = unambiguous(byNormalizedKey[Self.normalizedKey(name)] ?? []) {
            return JefitNameResolutionResult(target: .existing(match), method: .normalized)
        }

        return JefitNameResolutionResult(target: .newCustom(name: name), method: .unmapped)
    }

    /// One catalog candidate, else one custom candidate, else nothing.
    private func unambiguous(_ candidates: [JefitLocalExercise]) -> JefitLocalExercise? {
        let catalog = candidates.filter { !$0.isCustom }
        if catalog.count == 1 { return catalog[0] }
        if catalog.isEmpty, candidates.count == 1 { return candidates[0] }
        return nil
    }

    // MARK: - Normalisation

    /// Trimmed, with internal whitespace runs collapsed.
    static func clean(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lowercased words, apostrophes dropped, other punctuation as word
    /// breaks, crude singular forms, sorted: "Bench Press - Barbell" and
    /// "Barbell Bench Presses" share a key.
    static func normalizedKey(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split { !($0.isLetter || $0.isNumber) }
            .map { singular(String($0)) }
            .sorted()
            .joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 2 else { return word }
        for suffix in ["sses", "shes", "ches", "xes", "zes"] where word.hasSuffix(suffix) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ies"), word.count > 4 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us") {
            return String(word.dropLast())
        }
        return word
    }
}
