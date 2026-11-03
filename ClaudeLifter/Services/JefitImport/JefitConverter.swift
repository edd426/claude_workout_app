import CryptoKit
import Foundation

struct JefitImportOptions: Sendable, Equatable {
    /// Use this boundary instead of detecting one. The dry run still reports
    /// how many set logs it contradicts.
    var unitBoundaryOverride: JefitUnitBoundary?
    var workoutName = "Jefit Workout"
    var restSeconds = 90
    /// Jefit can fill reps-only exercises with a constant dummy weight (10,
    /// on push-ups, crunches, pull-ups and the like). An exercise whose every
    /// set carries the same weight at or below this, over at least
    /// `placeholderMinimumSets` sets with no bodyweight sets among them, is
    /// imported as bodyweight. Nil turns the rule off.
    var placeholderWeightLimit: Double? = 10
    var placeholderMinimumSets = 5
    /// A session longer than this (a workout left open) ends at its last
    /// exercise log instead — the same rule as `WorkoutAutoFinishPolicy`.
    var longSessionLimit: TimeInterval = WorkoutAutoFinishPolicy.idleThreshold

    /// Every imported workout carries exactly this note, so imported history
    /// can be found (or removed) as a group without a new stored property.
    static let importNote = "Imported from Jefit"
}

/// How one distinct Jefit exercise name was resolved, with its volume.
struct JefitNameResolution: Sendable, Equatable {
    let jefitName: String
    let target: JefitExerciseTarget
    let method: JefitMappingMethod
    var entries = 0
    var sets = 0
}

struct JefitPlaceholderWeight: Sendable, Equatable {
    let jefitName: String
    /// In the unit it was logged in.
    let loggedWeight: Double
    let sets: Int
}

/// Everything the user should see before anything is written. Aggregates
/// only: no row ever appears here, just counts, names and line numbers.
struct JefitDryRunSummary: Sendable, Equatable {
    var workouts = 0
    var exerciseEntries = 0
    var sets = 0
    var firstWorkoutStart: Date?
    var lastWorkoutStart: Date?

    var unitBoundary: JefitUnitBoundary = .allPounds
    var unitBoundaryOverridden = false
    var unitEvidence = JefitUnitEvidence()
    var poundWorkouts = 0
    var kilogramWorkouts = 0

    /// Sorted by entries, most first.
    var resolutions: [JefitNameResolution] = []
    /// Distinct custom exercises the import creates (several Jefit names
    /// can share one).
    var newCustomExercises = 0
    var placeholderWeights: [JefitPlaceholderWeight] = []

    var unparseableRows: [JefitRowIssue] = []
    var malformedSetParts = 0
    /// `0x0` padding sets (Jefit leaves them on timed exercises).
    var emptySetsSkipped = 0
    /// Exercise logs with no usable set.
    var emptyEntriesSkipped = 0
    /// Sessions with nothing to import (no logs, or none usable).
    var emptySessionsSkipped = 0
    /// Log groups whose WORKOUT SESSIONS row is missing; imported anyway,
    /// timed from their log times.
    var orphanSessions = 0
    var longSessionsTrimmed = 0
    var skippedSections: [JefitSkippedSection] = []

    /// Bytes the new workouts and custom exercises add to every snapshot push.
    var estimatedSnapshotGrowthBytes = 0

    var unmappedNames: [JefitNameResolution] { resolutions.filter { $0.method == .unmapped } }
    var catalogNames: [JefitNameResolution] { resolutions.filter { $0.target.isCatalog } }
    var customNames: [JefitNameResolution] { resolutions.filter { !$0.target.isCatalog } }
}

struct JefitImportPlan: Sendable {
    let document: BackupDocument
    let summary: JefitDryRunSummary
}

/// Pure Jefit export → `BackupDocument` conversion (#166). No store access:
/// the caller supplies a mapper built from the phone's exercises, and the
/// result goes through `BackupService.importBackup`, which merges by id,
/// never overwrites, and preflights every exercise reference.
///
/// Every id is derived from Jefit's own ids (name-based UUIDs), so converting
/// the same file again yields the same document and importing it again adds
/// nothing.
enum JefitConverter {

    // MARK: - Units

    /// Kilograms rounded to 0.01, or nil for 0 (bodyweight in this app).
    static func kilograms(fromLogged weight: Double, unit: WeightUnit) -> Double? {
        guard weight > 0 else { return nil }
        let kilograms = unit == .lbs ? weight * JefitUnitBoundaryDetector.kilogramsPerPound : weight
        return (kilograms * 100).rounded() / 100
    }

    // MARK: - Identity

    /// Name-based (v5-style, SHA-1) UUID in a namespace private to this
    /// importer. Same name, same UUID, on every device and every run.
    static func stableId(_ name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: Array(name.utf8))
        var digest = Array(Insecure.SHA1.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
    }

    private static let namespace = UUID(uuid: (
        0x4A, 0x45, 0x46, 0x49, 0x54, 0x2D, 0x43, 0x4C,
        0x8A, 0x1F, 0x63, 0x6C, 0x2E, 0x31, 0x36, 0x36
    ))

    /// Id and `custom:` externalId for a custom exercise the import creates.
    /// Keyed on the case- and spacing-insensitive name, so re-running finds
    /// the same exercise.
    static func customExerciseIdentity(name: String) -> (id: UUID, externalId: String) {
        let key = JefitExerciseMapper.clean(name).lowercased()
        let id = stableId("jefit-custom-exercise-\(key)")
        return (id, "custom:\(customSlug(name)):\(id.uuidString.lowercased())")
    }

    /// The server's custom-exercise slug grammar (`customExerciseIdentity.ts`):
    /// NFKD, combining marks dropped, non-alphanumeric runs → `-`, ≤ 64 chars.
    static func customSlug(_ name: String) -> String {
        let folded = name.decomposedStringWithCompatibilityMapping.unicodeScalars
            .filter { !(0x0300...0x036F).contains($0.value) }
        var slug = ""
        var pendingDash = false
        for scalar in folded {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !slug.isEmpty { slug.append("-") }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        slug = String(slug.lowercased().prefix(64))
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug.isEmpty ? "exercise" : slug
    }

    // MARK: - Conversion

    /// A workout to be: a session row with logs, or an orphan log group.
    private struct Unit {
        let key: String
        let start: Date
        let end: Date?
        let totalTime: TimeInterval?
        let logs: [JefitExerciseLog]
    }

    static func convert(
        _ export: JefitExport,
        mapper: JefitExerciseMapper,
        options: JefitImportOptions = JefitImportOptions()
    ) -> JefitImportPlan {
        var summary = JefitDryRunSummary()
        summary.unparseableRows = export.issues
        summary.skippedSections = export.skippedSections

        // 1. Group logs into units, in a stable chronological order.
        let units = makeUnits(export, summary: &summary)

        // 2. Parse every logs string once; drop 0x0 padding.
        var parsed: [String: [JefitLoggedSet]] = [:]
        for log in export.exerciseLogs {
            let result = JefitLogParser.parse(log.logs)
            summary.malformedSetParts += result.malformedParts
            let kept = result.sets.filter { $0.weight > 0 || $0.reps > 0 }
            summary.emptySetsSkipped += result.sets.count - kept.count
            parsed[log.id] = kept
        }

        // 3. Exercises whose "weight" is Jefit's constant dummy.
        let placeholders = placeholderWeights(export.exerciseLogs, parsed: parsed, options: options)
        summary.placeholderWeights = placeholders.sorted { $0.jefitName < $1.jefitName }
        let placeholderNames = Set(placeholders.map(\.jefitName))

        // 4. Units: detect (or take) the lb→kg boundary.
        let detection = detectBoundary(
            units: units, export: export, parsed: parsed,
            placeholderNames: placeholderNames, options: options
        )
        summary.unitBoundary = detection.boundary
        summary.unitEvidence = detection.evidence
        summary.unitBoundaryOverridden = options.unitBoundaryOverride != nil

        // 5. Build workouts.
        var resolutions: [String: JefitNameResolution] = [:]
        var newCustomNames: [String: String] = [:]   // identity key → display name
        var workouts: [WorkoutDTO] = []

        for unit in units {
            let loggedIn = detection.boundary.unit(at: unit.start)
            let completedAt = completion(of: unit, options: options, summary: &summary)

            var entries: [WorkoutExerciseDTO] = []
            for log in unit.logs {
                let sets = parsed[log.id] ?? []
                guard !sets.isEmpty else {
                    summary.emptyEntriesSkipped += 1
                    continue
                }
                let jefitName = JefitExerciseMapper.clean(log.exerciseName)
                var resolution = resolutions[jefitName] ?? {
                    let result = mapper.resolve(jefitName)
                    return JefitNameResolution(jefitName: jefitName, target: result.target, method: result.method)
                }()

                let exerciseId: UUID
                switch resolution.target {
                case .existing(let exercise):
                    exerciseId = exercise.id
                case .newCustom(let name):
                    let key = JefitExerciseMapper.clean(name).lowercased()
                    if newCustomNames[key] == nil { newCustomNames[key] = name }
                    exerciseId = customExerciseIdentity(name: name).id
                }

                let isPlaceholder = placeholderNames.contains(jefitName)
                let setTime = clamp(log.logTime ?? completedAt, unit.start, completedAt)
                let setDTOs = sets.enumerated().map { order, set in
                    WorkoutSetDTO(
                        id: stableId("jefit-set-\(log.id)-\(set.index)"),
                        order: order,
                        weight: isPlaceholder ? nil : kilograms(fromLogged: set.weight, unit: loggedIn),
                        weightUnit: WeightUnit.kg.rawValue,
                        reps: set.reps,
                        isCompleted: true,
                        completedAt: setTime,
                        notes: nil
                    )
                }
                let targetName = resolution.target.name
                entries.append(WorkoutExerciseDTO(
                    id: stableId("jefit-exercise-log-\(log.id)"),
                    exerciseId: exerciseId,
                    exerciseName: targetName,
                    order: entries.count,
                    notes: targetName == jefitName ? nil : "Jefit: \(jefitName)",
                    restSeconds: options.restSeconds,
                    sets: setDTOs
                ))

                resolution.entries += 1
                resolution.sets += setDTOs.count
                resolutions[jefitName] = resolution
            }

            guard !entries.isEmpty else {
                summary.emptySessionsSkipped += 1
                continue
            }
            switch loggedIn {
            case .lbs: summary.poundWorkouts += 1
            case .kg: summary.kilogramWorkouts += 1
            }
            summary.exerciseEntries += entries.count
            summary.sets += entries.reduce(0) { $0 + $1.sets.count }
            workouts.append(WorkoutDTO(
                id: stableId("jefit-session-\(unit.key)"),
                templateId: nil,
                name: options.workoutName,
                startedAt: unit.start,
                completedAt: completedAt,
                notes: JefitImportOptions.importNote,
                lastModified: completedAt,
                exercises: entries
            ))
        }

        // 6. Custom exercises the import creates.
        let customExercises = newCustomNames.values.sorted().map { name in
            let identity = customExerciseIdentity(name: name)
            return ExerciseDTO(
                id: identity.id,
                name: name,
                force: nil,
                level: nil,
                mechanic: nil,
                equipment: nil,
                instructions: [],
                primaryMuscles: [],
                secondaryMuscles: [],
                isCustom: true,
                externalId: identity.externalId,
                notes: JefitImportOptions.importNote,
                imageURL: nil,
                photoURL: nil,
                tags: []
            )
        }

        summary.unparseableRows.sort { ($0.line, $0.section) < ($1.line, $1.section) }
        summary.newCustomExercises = customExercises.count
        summary.workouts = workouts.count
        summary.firstWorkoutStart = workouts.first?.startedAt
        summary.lastWorkoutStart = workouts.last?.startedAt
        summary.resolutions = resolutions.values.sorted {
            ($0.entries, $1.jefitName) > ($1.entries, $0.jefitName)
        }
        let encoder = NetworkService.makeWireEncoder()
        summary.estimatedSnapshotGrowthBytes =
            ((try? encoder.encode(workouts).count) ?? 0) + ((try? encoder.encode(customExercises).count) ?? 0)

        let document = BackupDocument(
            formatVersion: 3,
            exportedAt: workouts.compactMap(\.completedAt).max() ?? Date(timeIntervalSince1970: 0),
            workouts: workouts,
            templates: [],
            customExercises: customExercises,
            preferences: []
        )
        return JefitImportPlan(document: document, summary: summary)
    }

    // MARK: - Steps

    private static func makeUnits(_ export: JefitExport, summary: inout JefitDryRunSummary) -> [Unit] {
        let logsBySession = Dictionary(grouping: export.exerciseLogs, by: \.sessionId)
        let orderedLogs: ([JefitExerciseLog]) -> [JefitExerciseLog] = { logs in
            logs.sorted { (Int($0.id) ?? .max, $0.id) < (Int($1.id) ?? .max, $1.id) }
        }

        var units: [Unit] = []
        var knownSessions = Set<String>()
        for session in export.sessions {
            knownSessions.insert(session.id)
            guard let logs = logsBySession[session.id], !logs.isEmpty else {
                summary.emptySessionsSkipped += 1
                continue
            }
            units.append(Unit(
                key: session.id, start: session.start, end: session.end,
                totalTime: session.totalTime, logs: orderedLogs(logs)
            ))
        }

        // Logs whose session row is missing: never dropped. Timed from their
        // own log times, or noon UTC on their date.
        for (sessionId, logs) in logsBySession where !knownSessions.contains(sessionId) {
            let times = logs.compactMap(\.logTime)
            guard let start = times.min() ?? logs.compactMap({ noonUTC($0.date) }).min() else {
                summary.unparseableRows += logs.map {
                    JefitRowIssue(section: JefitExport.logsSection, line: $0.line, reason: "no session and no usable date")
                }
                continue
            }
            summary.orphanSessions += 1
            let end = times.max().flatMap { $0 > start ? $0 : nil }
            units.append(Unit(
                key: "orphan-\(sessionId)", start: start, end: end,
                totalTime: nil, logs: orderedLogs(logs)
            ))
        }
        return units.sorted { ($0.start, $0.key) < ($1.start, $1.key) }
    }

    private static func placeholderWeights(
        _ logs: [JefitExerciseLog],
        parsed: [String: [JefitLoggedSet]],
        options: JefitImportOptions
    ) -> [JefitPlaceholderWeight] {
        guard let limit = options.placeholderWeightLimit else { return [] }
        let byName = Dictionary(grouping: logs) { JefitExerciseMapper.clean($0.exerciseName) }
        return byName.compactMap { name, logs in
            let weights = logs.flatMap { parsed[$0.id] ?? [] }.map(\.weight)
            guard
                weights.count >= options.placeholderMinimumSets,
                let first = weights.first,
                first > 0, first <= limit,
                weights.allSatisfy({ $0 == first })
            else { return nil }
            return JefitPlaceholderWeight(jefitName: name, loggedWeight: first, sets: weights.count)
        }
    }

    private static func detectBoundary(
        units: [Unit],
        export: JefitExport,
        parsed: [String: [JefitLoggedSet]],
        placeholderNames: Set<String>,
        options: JefitImportOptions
    ) -> JefitUnitDetection {
        let starts = units.map(\.start)
        var unitIndexByLog: [String: Int] = [:]
        var observations: [JefitUnitObservation] = []
        for (index, unit) in units.enumerated() {
            for log in unit.logs {
                unitIndexByLog[log.id] = index
                let name = JefitExerciseMapper.clean(log.exerciseName)
                guard !placeholderNames.contains(name),
                      let top = parsed[log.id]?.map(\.weight).max(), top > 0 else { continue }
                observations.append(JefitUnitObservation(
                    sessionIndex: index, exerciseKey: name.lowercased(), topWeight: top
                ))
            }
        }

        let direct: [JefitDirectUnitEvidence] = export.setLogs.compactMap { setLog in
            guard
                let index = unitIndexByLog[setLog.exerciseLogId],
                let logged = parsed[setLog.exerciseLogId]?.first(where: { $0.index == setLog.setIndex }),
                let unit = JefitUnitBoundaryDetector.classify(loggedWeight: logged.weight, weightLbs: setLog.weightLbs)
            else { return nil }
            return JefitDirectUnitEvidence(sessionIndex: index, unit: unit)
        }

        if let override = options.unitBoundaryOverride {
            return JefitUnitDetection(
                boundary: override,
                evidence: JefitUnitBoundaryDetector.evaluate(
                    boundary: override, sessionStarts: starts,
                    observations: observations, direct: direct
                )
            )
        }
        return JefitUnitBoundaryDetector.detect(
            sessionStarts: starts,
            observations: observations,
            direct: direct,
            currentUnitSetting: export.currentUnitSetting
        )
    }

    /// Session end, else start + total_time, else the last log time. A
    /// session left open for hours ends at its last log within the window.
    private static func completion(
        of unit: Unit,
        options: JefitImportOptions,
        summary: inout JefitDryRunSummary
    ) -> Date {
        let logTimes = unit.logs.compactMap(\.logTime)
        let end = unit.end
            ?? unit.totalTime.map { unit.start.addingTimeInterval($0) }
            ?? logTimes.filter { $0 > unit.start }.max()
            ?? unit.start
        guard end.timeIntervalSince(unit.start) > options.longSessionLimit else { return end }
        if let lastLog = logTimes.filter({ $0 > unit.start && $0 <= end }).max() {
            summary.longSessionsTrimmed += 1
            return lastLog
        }
        return end
    }

    private static func clamp(_ date: Date, _ lower: Date, _ upper: Date) -> Date {
        min(max(date, lower), upper)
    }

    private static func noonUTC(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)?.addingTimeInterval(12 * 3600)
    }
}
