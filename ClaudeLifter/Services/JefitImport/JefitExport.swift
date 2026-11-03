import Foundation

enum JefitImportError: Error, Equatable, LocalizedError {
    /// The file has no WORKOUT SESSIONS / EXERCISE LOGS sections — most often
    /// a Jefit export that was opened and re-saved in a spreadsheet app, which
    /// flattens the `### NAME ###` structure.
    case notAJefitExport
    /// A section the importer needs is missing columns it reads.
    case missingColumns(section: String, columns: [String])
    /// `jefit_exercise_map.json` is not in the app bundle.
    case mappingTableMissing

    var errorDescription: String? {
        switch self {
        case .mappingTableMissing:
            return "The Jefit exercise mapping table is missing from the app."
        case .notAJefitExport:
            return "This doesn't look like a Jefit export: no WORKOUT SESSIONS or EXERCISE LOGS section was found. Use the original file — re-saving it in a spreadsheet app breaks its sections."
        case .missingColumns(let section, let columns):
            return "The Jefit export's \(section) section is missing \(columns.joined(separator: ", "))."
        }
    }
}

struct JefitSession: Sendable, Equatable {
    let id: String
    let start: Date
    /// Nil when Jefit recorded no usable end (0, empty, or not after start).
    let end: Date?
    /// Seconds; nil when absent or not positive.
    let totalTime: TimeInterval?
    let line: Int
}

struct JefitExerciseLog: Sendable, Equatable {
    let id: String
    let sessionId: String
    /// `mydate`, `yyyy-MM-dd`.
    let date: String
    /// `ename` exactly as exported (Jefit sometimes leaves a trailing space).
    let exerciseName: String
    /// `belongSys == 0`: an exercise the user created in Jefit.
    let isJefitCustom: Bool
    let logs: String
    let logTime: Date?
    let line: Int
}

struct JefitSetLog: Sendable, Equatable {
    let exerciseLogId: String
    let setIndex: Int
    /// Jefit's own pound figure for the set, whatever unit it was logged in.
    let weightLbs: Double
    let line: Int
}

struct JefitCustomExercise: Sendable, Equatable {
    let id: String
    let name: String
}

/// A row the importer could not use. Carries the line, never the content:
/// the dry-run summary must not echo logged data.
struct JefitRowIssue: Sendable, Equatable {
    let section: String
    let line: Int
    let reason: String
}

struct JefitSkippedSection: Sendable, Equatable {
    let name: String
    let rows: Int
}

/// The parts of a Jefit export the history import reads (#166). Cardio,
/// profile/body measurements, routines, notes, records and favourites are
/// out of scope and only counted.
struct JefitExport: Sendable {
    var sessions: [JefitSession] = []
    var exerciseLogs: [JefitExerciseLog] = []
    var setLogs: [JefitSetLog] = []
    var customExercises: [JefitCustomExercise] = []
    /// SETTING `mass`: the unit Jefit is set to now, i.e. the unit of the
    /// most recent logs. Nil when the section or value is missing.
    var currentUnitSetting: WeightUnit?
    var skippedSections: [JefitSkippedSection] = []
    var issues: [JefitRowIssue] = []

    static let sessionsSection = "WORKOUT SESSIONS"
    static let logsSection = "EXERCISE LOGS"
    static let setLogsSection = "EXERCISE SET LOGS"
    static let customsSection = "CUSTOM EXERCISES"
    static let settingSection = "SETTING"

    static func parse(_ text: String) throws -> JefitExport {
        let sections = JefitCSV.sections(in: text)
        guard
            let sessionsSection = sections.first(where: { $0.name == Self.sessionsSection }),
            let logsSection = sections.first(where: { $0.name == Self.logsSection })
        else {
            throw JefitImportError.notAJefitExport
        }

        var export = JefitExport()
        export.sessions = try parseSessions(sessionsSection, issues: &export.issues)
        export.exerciseLogs = try parseLogs(logsSection, issues: &export.issues)
        if let section = sections.first(where: { $0.name == Self.setLogsSection }), !section.header.isEmpty {
            export.setLogs = try parseSetLogs(section, issues: &export.issues)
        }
        if let section = sections.first(where: { $0.name == Self.customsSection }), !section.header.isEmpty {
            export.customExercises = try parseCustoms(section, issues: &export.issues)
        }
        if let section = sections.first(where: { $0.name == Self.settingSection }),
           let row = section.rows.first,
           let mass = section.value("mass", in: row)?.trimmingCharacters(in: .whitespaces).lowercased() {
            if mass.hasPrefix("kg") {
                export.currentUnitSetting = .kg
            } else if mass.hasPrefix("lb") {
                export.currentUnitSetting = .lbs
            }
        }

        let used: Set<String> = [
            Self.sessionsSection, Self.logsSection, Self.setLogsSection,
            Self.customsSection, Self.settingSection,
        ]
        export.skippedSections = sections
            .filter { !used.contains($0.name) }
            .map { JefitSkippedSection(name: $0.name, rows: $0.rows.count) }
        return export
    }

    // MARK: - Sections

    private static func parseSessions(
        _ section: JefitSection,
        issues: inout [JefitRowIssue]
    ) throws -> [JefitSession] {
        try require(["_id", "starttime"], in: section)
        var sessions: [JefitSession] = []
        var seen = Set<String>()
        for row in wellFormedRows(of: section, issues: &issues) {
            guard
                let id = section.value("_id", in: row)?.trimmed, !id.isEmpty,
                let startSeconds = section.value("starttime", in: row).flatMap(epochSeconds),
                startSeconds > 0
            else {
                issues.append(JefitRowIssue(section: section.name, line: row.line, reason: "missing session id or start time"))
                continue
            }
            // Ids seed the imported records' UUIDs; a repeat would collide.
            guard seen.insert(id).inserted else {
                issues.append(JefitRowIssue(section: section.name, line: row.line, reason: "duplicate session id"))
                continue
            }
            let endSeconds = section.value("endtime", in: row).flatMap(epochSeconds)
            let total = section.value("total_time", in: row).flatMap { Double($0.trimmed) }
            sessions.append(JefitSession(
                id: id,
                start: Date(timeIntervalSince1970: startSeconds),
                end: endSeconds.flatMap { $0 > startSeconds ? Date(timeIntervalSince1970: $0) : nil },
                totalTime: total.flatMap { $0 > 0 ? $0 : nil },
                line: row.line
            ))
        }
        return sessions
    }

    private static func parseLogs(
        _ section: JefitSection,
        issues: inout [JefitRowIssue]
    ) throws -> [JefitExerciseLog] {
        try require(["_id", "ename", "belongsession", "logs"], in: section)
        var logs: [JefitExerciseLog] = []
        var seen = Set<String>()
        for row in wellFormedRows(of: section, issues: &issues) {
            guard
                let id = section.value("_id", in: row)?.trimmed, !id.isEmpty,
                let name = section.value("ename", in: row), !name.trimmed.isEmpty,
                let sessionId = section.value("belongsession", in: row)?.trimmed
            else {
                issues.append(JefitRowIssue(section: section.name, line: row.line, reason: "missing log id or exercise name"))
                continue
            }
            guard seen.insert(id).inserted else {
                issues.append(JefitRowIssue(section: section.name, line: row.line, reason: "duplicate log id"))
                continue
            }
            let logTime = section.value("logTime", in: row)
                .flatMap(epochSeconds)
                .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            logs.append(JefitExerciseLog(
                id: id,
                sessionId: sessionId,
                date: section.value("mydate", in: row)?.trimmed ?? "",
                exerciseName: name,
                isJefitCustom: section.value("belongSys", in: row)?.trimmed == "0",
                logs: section.value("logs", in: row) ?? "",
                logTime: logTime,
                line: row.line
            ))
        }
        return logs
    }

    private static func parseSetLogs(
        _ section: JefitSection,
        issues: inout [JefitRowIssue]
    ) throws -> [JefitSetLog] {
        try require(["exercise_log_id", "set_index", "weight_lbs"], in: section)
        return wellFormedRows(of: section, issues: &issues).compactMap { row in
            // Evidence only: a set log without numbers is unhelpful, not an error.
            guard
                let logId = section.value("exercise_log_id", in: row)?.trimmed, !logId.isEmpty,
                let index = section.value("set_index", in: row).flatMap({ Int($0.trimmed) }),
                let pounds = section.value("weight_lbs", in: row).flatMap({ Double($0.trimmed) })
            else { return nil }
            return JefitSetLog(exerciseLogId: logId, setIndex: index, weightLbs: pounds, line: row.line)
        }
    }

    private static func parseCustoms(
        _ section: JefitSection,
        issues: inout [JefitRowIssue]
    ) throws -> [JefitCustomExercise] {
        try require(["_id", "name"], in: section)
        return wellFormedRows(of: section, issues: &issues).compactMap { row in
            guard
                let id = section.value("_id", in: row)?.trimmed,
                let name = section.value("name", in: row)?.trimmed, !name.isEmpty
            else { return nil }
            return JefitCustomExercise(id: id, name: name)
        }
    }

    // MARK: - Helpers

    private static func require(_ columns: [String], in section: JefitSection) throws {
        let missing = columns.filter { !section.header.contains($0) }
        guard missing.isEmpty else {
            throw JefitImportError.missingColumns(section: section.name, columns: missing)
        }
    }

    /// Rows whose field count matches the header; the rest become issues.
    private static func wellFormedRows(
        of section: JefitSection,
        issues: inout [JefitRowIssue]
    ) -> [JefitRow] {
        section.rows.filter { row in
            guard row.fields.count == section.header.count else {
                issues.append(JefitRowIssue(
                    section: section.name,
                    line: row.line,
                    reason: "expected \(section.header.count) columns, found \(row.fields.count)"
                ))
                return false
            }
            return true
        }
    }

    /// Jefit writes times as whole epoch seconds; tolerate a decimal part.
    private static func epochSeconds(_ text: String) -> TimeInterval? {
        Double(text.trimmed)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
