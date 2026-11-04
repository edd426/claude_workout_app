import Foundation

/// Where personal records start counting (Evan, 2026-11-03).
///
/// Sets from this day on are the bar a new set has to beat. Older history,
/// including the 2019–2025 Jefit import (#166), is shown beside a record as
/// the lifetime best, for reference only: it never blocks a record.
enum PREra {
    /// 1 January 2026, local midnight. The one place the era is defined.
    static let start: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        // 1_767_225_600 is 2026-01-01T00:00:00Z, for a calendar that can't
        // build the date (it always can under Gregorian).
        return calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
            ?? Date(timeIntervalSince1970: 1_767_225_600)
    }()

    /// "since 2026", the label every record carries.
    static var label: String {
        "since \(Calendar(identifier: .gregorian).component(.year, from: start))"
    }
}

/// One completed, weighted set from a finished workout, reduced to what a
/// PR baseline needs. Weight is always kilograms, converted from the set's
/// own unit.
struct PRHistorySet: Equatable, Sendable {
    let exerciseId: UUID
    let externalId: String?
    let weightKg: Double
    let reps: Int
    /// The workout's start.
    let date: Date
}

/// A set as a record shows it: kilograms, reps, when.
struct PRSetRef: Equatable, Sendable {
    let weightKg: Double
    let reps: Int
    let date: Date

    /// Brzycki, as `PersonalRecord.estimated1RM`; nil above 36 reps.
    var estimated1RM: Double? {
        guard reps <= 36 else { return nil }
        return weightKg * (36.0 / (37.0 - Double(reps)))
    }
}

/// What a finished workout achieved, for the summary (#173).
struct PRReport: Equatable, Sendable {
    struct Record: Equatable, Sendable, Identifiable {
        /// The exercise as logged in this workout.
        let exerciseId: UUID
        let exerciseName: String
        let type: PRType
        /// Kilograms for heaviest weight and estimated 1RM; reps for most
        /// reps at a weight.
        let value: Double
        /// The set that set the record.
        let set: PRSetRef
        /// The best earlier set by the same measure, at any date. Nil when
        /// there is no earlier history at all.
        let lifetimeBest: PRSetRef?

        var id: String {
            "\(exerciseId)|\(type.rawValue)|\(set.weightKg)|\(set.reps)"
        }

        /// True when no earlier set, of any year, matches this one.
        var isNewLifetimeBest: Bool {
            guard let lifetimeBest else { return true }
            switch type {
            case .heaviestWeight:
                return set.weightKg > lifetimeBest.weightKg + PRReportBuilder.tolerance
            case .highest1RM:
                return (set.estimated1RM ?? 0) > (lifetimeBest.estimated1RM ?? 0) + PRReportBuilder.tolerance
            case .mostRepsAtWeight:
                return set.reps > lifetimeBest.reps
            }
        }
    }

    /// An exercise done today with no record since the era start: its
    /// heaviest set ever, for comparison.
    struct LifetimeReference: Equatable, Sendable, Identifiable {
        let exerciseId: UUID
        let exerciseName: String
        let heaviest: PRSetRef

        var id: UUID { exerciseId }
    }

    var records: [Record] = []
    var lifetimeReferences: [LifetimeReference] = []
}

/// Pure record detection for one exercise. No store access, so it is the
/// same computation whether called while saving records or while reading
/// them back for the summary.
enum PRReportBuilder {
    /// Kilograms. Converted weights rarely match exactly: 100 lb is
    /// 45.359 kg, and the Jefit import rounds it to 45.36.
    static let tolerance = 0.05

    /// The earlier best of each measure since the era start. Stored records
    /// count too: the same exercise row's records are real evidence when
    /// they exist, they just can't be the only evidence (#173).
    struct EraBaseline {
        var heaviestKg: Double?
        var best1RM: Double?
        /// (kg, reps) points; a set is a reps record only if no point is at
        /// least as heavy with at least as many reps.
        var repPoints: [(weightKg: Double, reps: Int)] = []
    }

    static func baseline(
        history: [PRSetRef],
        storedRecords: [PersonalRecord],
        eraStart: Date
    ) -> EraBaseline {
        let era = history.filter { $0.date >= eraStart }
        let storedEra = storedRecords.filter { $0.achievedAt >= eraStart }
        var baseline = EraBaseline()
        let weights = era.map(\.weightKg)
            + storedEra.filter { $0.prType == .heaviestWeight }.map(\.value)
        baseline.heaviestKg = weights.max()
        let oneRMs = era.compactMap(\.estimated1RM)
            + storedEra.filter { $0.prType == .highest1RM }.map(\.value)
        baseline.best1RM = oneRMs.max()
        baseline.repPoints = era.map { ($0.weightKg, $0.reps) }
            + storedEra.compactMap { record in
                guard record.prType == .mostRepsAtWeight,
                      let weight = record.weight, let reps = record.reps
                else { return nil }
                return (weight, reps)
            }
        return baseline
    }

    /// Records one exercise set today against its baseline, each with the
    /// lifetime best of the same measure beside it.
    static func records(
        exerciseId: UUID,
        exerciseName: String,
        today: [PRSetRef],
        baseline: EraBaseline,
        lifetime: [PRSetRef]
    ) -> [PRReport.Record] {
        func record(_ type: PRType, _ value: Double, _ set: PRSetRef, _ best: PRSetRef?) -> PRReport.Record {
            PRReport.Record(
                exerciseId: exerciseId, exerciseName: exerciseName,
                type: type, value: value, set: set, lifetimeBest: best
            )
        }
        var found: [PRReport.Record] = []

        if let top = heaviest(today),
           top.weightKg > (baseline.heaviestKg ?? -.infinity) + tolerance {
            found.append(record(.heaviestWeight, top.weightKg, top, heaviest(lifetime)))
        }

        for set in repsFront(today) where !isDominated(set, by: baseline.repPoints) {
            found.append(record(.mostRepsAtWeight, Double(set.reps), set, mostReps(atLeast: set.weightKg, in: lifetime)))
        }

        if let top = best1RM(today), let value = top.estimated1RM,
           value > (baseline.best1RM ?? -.infinity) + tolerance {
            found.append(record(.highest1RM, value, top, best1RM(lifetime)))
        }
        return found
    }

    // MARK: - Measures

    /// Heaviest set; ties go to more reps, then the earlier date.
    static func heaviest(_ sets: [PRSetRef]) -> PRSetRef? {
        sets.max { lhs, rhs in
            if abs(lhs.weightKg - rhs.weightKg) > tolerance { return lhs.weightKg < rhs.weightKg }
            if lhs.reps != rhs.reps { return lhs.reps < rhs.reps }
            return lhs.date > rhs.date
        }
    }

    static func best1RM(_ sets: [PRSetRef]) -> PRSetRef? {
        sets.filter { $0.estimated1RM != nil }.max { lhs, rhs in
            let left = lhs.estimated1RM ?? 0
            let right = rhs.estimated1RM ?? 0
            if left != right { return left < right }
            return lhs.date > rhs.date
        }
    }

    /// Most reps at this weight or heavier; ties go to the heavier set.
    static func mostReps(atLeast weightKg: Double, in sets: [PRSetRef]) -> PRSetRef? {
        sets.filter { $0.weightKg >= weightKg - tolerance }.max { lhs, rhs in
            if lhs.reps != rhs.reps { return lhs.reps < rhs.reps }
            if abs(lhs.weightKg - rhs.weightKg) > tolerance { return lhs.weightKg < rhs.weightKg }
            return lhs.date > rhs.date
        }
    }

    static func isDominated(_ set: PRSetRef, by points: [(weightKg: Double, reps: Int)]) -> Bool {
        points.contains { $0.weightKg >= set.weightKg - tolerance && $0.reps >= set.reps }
    }

    /// Today's sets that no other set today beats on both weight and reps,
    /// one per weight. 60 × 10 and 60 × 8 leave 60 × 10; 62.5 × 10 also
    /// removes 60 × 10.
    static func repsFront(_ sets: [PRSetRef]) -> [PRSetRef] {
        var front: [PRSetRef] = []
        for set in sets.sorted(by: { $0.weightKg > $1.weightKg || ($0.weightKg == $1.weightKg && $0.reps > $1.reps) }) {
            let beaten = front.contains { $0.weightKg >= set.weightKg - tolerance && $0.reps >= set.reps }
            if !beaten { front.append(set) }
        }
        return front
    }
}

/// Text for records, always in the user's unit.
enum PRDisplay {
    /// "100 kg", "102.5 kg", "220.5 lbs". Kilograms keep two decimals for
    /// 1.25 kg plates; pounds round to a tenth.
    static func weight(_ kilograms: Double, in unit: WeightUnit) -> String {
        let value = WeightUnit.kg.convert(kilograms, to: unit)
        let digits = unit == .kg ? 0...2 : 0...1
        let number = value.formatted(.number.grouping(.never).precision(.fractionLength(digits)))
        return "\(number) \(unit.rawValue)"
    }

    /// "100 kg × 5".
    static func setText(_ set: PRSetRef, in unit: WeightUnit) -> String {
        "\(weight(set.weightKg, in: unit)) × \(set.reps)"
    }

    /// "2019" for an earlier year, "12 Oct" for this one.
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.day().month(.abbreviated))
        }
        return String(calendar.component(.year, from: date))
    }

    /// "lifetime best 100 kg × 5 · 2019".
    static func lifetimeBest(_ set: PRSetRef, in unit: WeightUnit, now: Date) -> String {
        "lifetime best \(setText(set, in: unit)) · \(when(set.date, now: now))"
    }

    /// What the record is, in words: "Heaviest since 2026".
    static func title(for type: PRType) -> String {
        switch type {
        case .heaviestWeight: return "Heaviest \(PREra.label)"
        case .mostRepsAtWeight: return "Most reps at this weight \(PREra.label)"
        case .highest1RM: return "Best estimated 1RM \(PREra.label)"
        }
    }

    /// The record's own figure: the set, or the 1RM it implies.
    static func value(of record: PRReport.Record, in unit: WeightUnit) -> String {
        switch record.type {
        case .heaviestWeight, .mostRepsAtWeight:
            return setText(record.set, in: unit)
        case .highest1RM:
            return "\(weight(record.value, in: unit)) (\(setText(record.set, in: unit)))"
        }
    }

    /// The comparison line beside a record.
    static func comparison(for record: PRReport.Record, in unit: WeightUnit, now: Date) -> String {
        guard let best = record.lifetimeBest else { return "First time logged" }
        if record.isNewLifetimeBest { return "New lifetime best" }
        if record.type == .highest1RM, let oneRM = best.estimated1RM {
            return "lifetime best \(weight(oneRM, in: unit)) (\(setText(best, in: unit))) · \(when(best.date, now: now))"
        }
        return lifetimeBest(best, in: unit, now: now)
    }
}
