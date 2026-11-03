import Testing
import Foundation
@testable import ClaudeLifter

@Suite("Jefit export parsing (#166)")
struct JefitParsingTests {

    // MARK: - Section parser

    @Test("Splits the export into its named sections")
    func splitsSections() {
        let sections = JefitCSV.sections(in: JefitFixtures.export)
        #expect(sections.map(\.name) == [
            "SETTING", "PROFILE", "ROUTINES", "WORKOUT SESSIONS", "EXERCISE LOGS",
            "EXERCISE SET LOGS", "EXERCISE RECORDS", "CARDIO LOGS", "CUSTOM EXERCISES",
            "FAVORITE EXERCISES", "NOTES",
        ])
    }

    @Test("First record is the header; data rows keep their line numbers")
    func headerAndRows() throws {
        let sections = JefitCSV.sections(in: JefitFixtures.export)
        let sessions = try #require(sections.first { $0.name == "WORKOUT SESSIONS" })
        #expect(sessions.header.contains("starttime"))
        #expect(sessions.rows.count == 5)
        let first = try #require(sessions.rows.first)
        #expect(sessions.value("_id", in: first) == "1001")
        #expect(first.line > 1)
    }

    @Test("Quoted fields keep their commas")
    func quotedCommas() throws {
        let logs = try #require(JefitCSV.sections(in: JefitFixtures.export).first { $0.name == "EXERCISE LOGS" })
        let first = try #require(logs.rows.first)
        #expect(logs.value("logs", in: first) == "225x5,235x5")
        #expect(logs.value("ename", in: first) == "Barbell Squat")
    }

    @Test("A quoted field may span lines and contain doubled quotes")
    func multilineAndEscapedQuotes() throws {
        let text = #"""
        ### NOTES ####
        a,b,c
        1,"line one
        line two, still ""quoted""",3
        ######
        """#
        let section = try #require(JefitCSV.sections(in: text).first)
        #expect(section.rows.count == 1)
        let row = try #require(section.rows.first)
        #expect(section.value("b", in: row) == "line one\nline two, still \"quoted\"")
        #expect(section.value("c", in: row) == "3")
    }

    @Test("CRLF line endings parse the same as LF")
    func crlf() throws {
        let text = "### WORKOUT SESSIONS ####\r\n_id,starttime\r\n7,100\r\n######\r\n"
        let section = try #require(JefitCSV.sections(in: text).first)
        #expect(section.header == ["_id", "starttime"])
        #expect(section.rows.first?.fields == ["7", "100"])
    }

    @Test("An empty section has no header and no rows")
    func emptySection() throws {
        let section = try #require(JefitCSV.sections(in: JefitFixtures.export).first { $0.name == "FAVORITE EXERCISES" })
        #expect(section.header.isEmpty)
        #expect(section.rows.isEmpty)
    }

    // MARK: - logs string

    @Test("Parses weight x reps pairs in order")
    func parsesPairs() {
        let result = JefitLogParser.parse("225x6,235x6")
        #expect(result.sets == [
            JefitLoggedSet(index: 0, weight: 225, reps: 6),
            JefitLoggedSet(index: 1, weight: 235, reps: 6),
        ])
        #expect(result.malformedParts == 0)
    }

    @Test("Keeps decimal weights exactly", arguments: [
        ("59.9998x12", 59.9998, 12),
        ("102.5x5", 102.5, 5),
        ("0x15", 0.0, 15),
        (" 20.0x15 ", 20.0, 15),
    ])
    func decimals(input: String, weight: Double, reps: Int) {
        let result = JefitLogParser.parse(input)
        #expect(result.sets == [JefitLoggedSet(index: 0, weight: weight, reps: reps)])
    }

    @Test("Malformed parts are counted and skipped; indices stay positional")
    func malformedParts() {
        let result = JefitLogParser.parse("50x8,abcx5,55x8,x6,225x,-5x5,1e3x5,22.5x6.5,7x7x7")
        #expect(result.sets == [
            JefitLoggedSet(index: 0, weight: 50, reps: 8),
            JefitLoggedSet(index: 2, weight: 55, reps: 8),
        ])
        #expect(result.malformedParts == 7)
    }

    @Test("An empty logs string has no sets and nothing malformed")
    func emptyLogs() {
        let result = JefitLogParser.parse("")
        #expect(result.sets.isEmpty)
        #expect(result.malformedParts == 0)
    }

    // MARK: - Typed export

    @Test("Typed export reads sessions, logs, set logs, customs and the unit setting")
    func typedExport() throws {
        let export = try JefitExport.parse(JefitFixtures.export)
        #expect(export.sessions.count == 5)
        #expect(export.exerciseLogs.count == 13)
        #expect(export.setLogs.count == 3)
        #expect(export.customExercises.map(\.name) == ["Zorbo Press"])
        #expect(export.currentUnitSetting == .kg)
        let s4 = try #require(export.sessions.first { $0.id == "1004" })
        #expect(s4.start == Date(timeIntervalSince1970: JefitFixtures.s4Start))
        #expect(s4.end == nil)
        #expect(s4.totalTime == 2700)
    }

    @Test("A row with the wrong column count is reported by line, never by content")
    func malformedRowReported() throws {
        let export = try JefitExport.parse(JefitFixtures.export)
        #expect(export.issues.count == 1)
        let issue = try #require(export.issues.first)
        #expect(issue.section == "EXERCISE LOGS")
        #expect(issue.line > 0)
        #expect(!issue.reason.contains("broken"))
    }

    @Test("Out-of-scope sections are listed as skipped with their row counts")
    func skippedSections() throws {
        let export = try JefitExport.parse(JefitFixtures.export)
        let skipped = Dictionary(uniqueKeysWithValues: export.skippedSections.map { ($0.name, $0.rows) })
        #expect(skipped["CARDIO LOGS"] == 1)
        #expect(skipped["PROFILE"] == 1)
        #expect(skipped["ROUTINES"] == 1)
        #expect(skipped["NOTES"] == 1)
        #expect(skipped["EXERCISE RECORDS"] == 1)
        #expect(skipped["FAVORITE EXERCISES"] == 0)
        #expect(skipped["WORKOUT SESSIONS"] == nil)
    }

    @Test("A repeated session or log id is reported and skipped (ids seed record UUIDs)")
    func duplicateIds() throws {
        let text = """
        ### WORKOUT SESSIONS ####
        _id,starttime,endtime
        1,1700000000,1700003600
        1,1700100000,1700103600
        ######
        ### EXERCISE LOGS ####
        _id,ename,belongsession,logs
        5,Barbell Squat,1,100x5
        5,Barbell Squat,1,110x5
        ######
        """
        let export = try JefitExport.parse(text)
        #expect(export.sessions.count == 1)
        #expect(export.exerciseLogs.count == 1)
        #expect(export.issues.map(\.reason) == ["duplicate session id", "duplicate log id"])
    }

    @Test("A file without the session and log sections is rejected")
    func notAJefitExport() {
        #expect(throws: JefitImportError.notAJefitExport) {
            try JefitExport.parse("name,reps\nbench,5\n")
        }
    }
}
