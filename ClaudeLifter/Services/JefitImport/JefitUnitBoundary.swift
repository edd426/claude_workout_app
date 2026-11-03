import Foundation

/// Which unit a Jefit `logs` weight is in. Jefit stores the number in the
/// unit in force when it was logged, so an account that switched from pounds
/// to kilograms has both in one file. The model is a single lb→kg switch at
/// a session start.
enum JefitUnitBoundary: Sendable, Equatable {
    case allPounds
    case allKilograms
    /// Sessions starting at or after the date were logged in kilograms.
    case kilograms(from: Date)

    func unit(at date: Date) -> WeightUnit {
        switch self {
        case .allPounds: return .lbs
        case .allKilograms: return .kg
        case .kilograms(let switchDate): return date >= switchDate ? .kg : .lbs
        }
    }
}

/// The heaviest set of one exercise in one session, as logged (raw number).
struct JefitUnitObservation: Sendable, Equatable {
    let sessionIndex: Int
    let exerciseKey: String
    let topWeight: Double
}

/// A set whose unit is known outright: EXERCISE SET LOGS carry `weight_lbs`,
/// so a log value equal to it was pounds and one 2.20462× smaller was kg.
struct JefitDirectUnitEvidence: Sendable, Equatable {
    let sessionIndex: Int
    let unit: WeightUnit
}

struct JefitUnitEvidence: Sendable, Equatable {
    /// Set logs whose `weight_lbs` equals the logged weight.
    var poundSetLogs = 0
    /// Set logs whose `weight_lbs` is the logged weight × 2.20462.
    var kilogramSetLogs = 0
    /// Set logs the chosen boundary disagrees with.
    var contradictingSetLogs = 0
    /// Consecutive sessions of one exercise whose top weights still differ by
    /// more than 1.6× after conversion under the chosen boundary — a measure
    /// of how well it explains the data, not an error count.
    var continuityJumps = 0
}

struct JefitUnitDetection: Sendable, Equatable {
    let boundary: JefitUnitBoundary
    let evidence: JefitUnitEvidence
}

/// Finds the lb→kg switch by scoring every session start as a candidate.
///
/// The cost of a candidate is the set logs it contradicts (weighted heavily —
/// they are direct evidence) plus the weight-continuity jumps it creates:
/// for each exercise, consecutive sessions should stay within 1.6× of each
/// other once both are in kilograms. Back squat 225 → 105 is a jump if both
/// are the same unit, and continuous if the first is pounds. The SETTING
/// `mass` value anchors which unit the newest data is in.
///
/// Ties go to "no switch" first (never invent one without evidence), then to
/// the candidate after the longest break in training — a move abroad leaves a
/// gap. Every candidate is scored in O(sessions + observations) with
/// difference arrays, so a 900-session export costs nothing.
enum JefitUnitBoundaryDetector {
    static let poundsPerKilogram = 2.20462
    static let kilogramsPerPound = 0.45359237
    static let jumpRatio = 1.6
    static let directEvidenceWeight = 5
    static let settingPenalty = 1_000

    /// The unit a set log proves, or nil when the figures match neither.
    static func classify(loggedWeight: Double, weightLbs: Double) -> WeightUnit? {
        guard loggedWeight > 0, weightLbs > 0 else { return nil }
        let ratio = weightLbs / loggedWeight
        if abs(ratio - 1) <= 0.02 { return .lbs }
        if abs(ratio - poundsPerKilogram) <= 0.05 { return .kg }
        return nil
    }

    /// `sessionStarts` must be ascending; indices in `observations` and
    /// `direct` refer into it.
    static func detect(
        sessionStarts: [Date],
        observations: [JefitUnitObservation],
        direct: [JefitDirectUnitEvidence],
        currentUnitSetting: WeightUnit?
    ) -> JefitUnitDetection {
        let n = sessionStarts.count
        guard n > 0 else {
            return JefitUnitDetection(boundary: .allPounds, evidence: JefitUnitEvidence())
        }
        let observations = observations.filter { (0..<n).contains($0.sessionIndex) }

        // Candidate k (0...n): sessions with index >= k are kilograms.
        // k == 0 is "all kg", k == n is "all lb".
        var continuityDelta = [Int](repeating: 0, count: n + 2)
        var directDelta = [Int](repeating: 0, count: n + 2)
        var continuityBase = 0

        func addContinuity(_ amount: Int, from lower: Int, through upper: Int) {
            guard amount != 0, lower <= upper else { return }
            continuityDelta[lower] += amount
            continuityDelta[upper + 1] -= amount
        }

        for pair in consecutivePairs(observations) {
            let sameUnitJump = isJump(pair.later.topWeight / pair.earlier.topWeight)
            let splitJump = isJump(pair.later.topWeight / (pair.earlier.topWeight * kilogramsPerPound))
            // Same unit when k <= earlier or k > later; split for k in (earlier, later].
            continuityBase += sameUnitJump ? 1 : 0
            addContinuity(
                (splitJump ? 1 : 0) - (sameUnitJump ? 1 : 0),
                from: pair.earlier.sessionIndex + 1,
                through: pair.later.sessionIndex
            )
        }

        for evidence in direct where (0..<n).contains(evidence.sessionIndex) {
            let s = evidence.sessionIndex
            switch evidence.unit {
            case .kg:
                // Wrong whenever session s is classed as pounds: k > s.
                directDelta[s + 1] += 1
                directDelta[n + 1] -= 1
            case .lbs:
                // Wrong whenever session s is classed as kilograms: k <= s.
                directDelta[0] += 1
                directDelta[s + 1] -= 1
            }
        }

        var best: (k: Int, key: (Int, Int, Int, Double))?
        var continuityRunning = continuityBase
        var directRunning = 0
        for k in 0...n {
            continuityRunning += continuityDelta[k]
            directRunning += directDelta[k]

            var cost = continuityRunning + directEvidenceWeight * directRunning
            switch currentUnitSetting {
            case .kg?: if k == n { cost += settingPenalty }
            case .lbs?: if k < n { cost += settingPenalty }
            case nil: break
            }
            let interior = (k > 0 && k < n) ? 1 : 0
            let preferPounds = k == n ? 0 : 1
            let gap = interior == 1
                ? sessionStarts[k].timeIntervalSince(sessionStarts[k - 1])
                : 0
            let key = (cost, interior, preferPounds, -gap)
            if best == nil || key < (best?.key ?? key) {
                best = (k, key)
            }
        }

        let chosen = best?.k ?? n
        let boundary: JefitUnitBoundary
        switch chosen {
        case 0: boundary = .allKilograms
        case n: boundary = .allPounds
        default: boundary = .kilograms(from: sessionStarts[chosen])
        }

        return JefitUnitDetection(
            boundary: boundary,
            evidence: evaluate(
                boundary: boundary,
                sessionStarts: sessionStarts,
                observations: observations,
                direct: direct
            )
        )
    }

    /// How well `boundary` explains the data — used for the detected boundary
    /// and for a caller's override alike, so the dry run can show when an
    /// override contradicts the set logs.
    static func evaluate(
        boundary: JefitUnitBoundary,
        sessionStarts: [Date],
        observations: [JefitUnitObservation],
        direct: [JefitDirectUnitEvidence]
    ) -> JefitUnitEvidence {
        func unit(_ index: Int) -> WeightUnit { boundary.unit(at: sessionStarts[index]) }
        func kilograms(_ observation: JefitUnitObservation) -> Double {
            unit(observation.sessionIndex) == .lbs
                ? observation.topWeight * kilogramsPerPound
                : observation.topWeight
        }

        var evidence = JefitUnitEvidence()
        for item in direct where sessionStarts.indices.contains(item.sessionIndex) {
            switch item.unit {
            case .lbs: evidence.poundSetLogs += 1
            case .kg: evidence.kilogramSetLogs += 1
            }
            if unit(item.sessionIndex) != item.unit {
                evidence.contradictingSetLogs += 1
            }
        }
        let valid = observations.filter { sessionStarts.indices.contains($0.sessionIndex) }
        for pair in consecutivePairs(valid) where isJump(kilograms(pair.later) / kilograms(pair.earlier)) {
            evidence.continuityJumps += 1
        }
        return evidence
    }

    private static func isJump(_ ratio: Double) -> Bool {
        guard ratio.isFinite, ratio > 0 else { return false }
        return abs(log(ratio)) > log(jumpRatio)
    }

    /// For each exercise, chronologically consecutive sessions with a weight.
    private static func consecutivePairs(
        _ observations: [JefitUnitObservation]
    ) -> [(earlier: JefitUnitObservation, later: JefitUnitObservation)] {
        let byExercise = Dictionary(grouping: observations.filter { $0.topWeight > 0 }, by: \.exerciseKey)
        var pairs: [(earlier: JefitUnitObservation, later: JefitUnitObservation)] = []
        for key in byExercise.keys.sorted() {
            // One observation per session: the heaviest, if logged twice.
            var perSession: [Int: JefitUnitObservation] = [:]
            for observation in byExercise[key] ?? [] {
                if let existing = perSession[observation.sessionIndex],
                   existing.topWeight >= observation.topWeight { continue }
                perSession[observation.sessionIndex] = observation
            }
            let ordered = perSession.values.sorted { $0.sessionIndex < $1.sessionIndex }
            for (earlier, later) in zip(ordered, ordered.dropFirst()) {
                pairs.append((earlier, later))
            }
        }
        return pairs
    }
}
