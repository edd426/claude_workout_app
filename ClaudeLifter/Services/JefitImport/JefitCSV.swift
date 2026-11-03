import Foundation

/// One CSV record of a Jefit export. `line` is the 1-based line where the
/// record starts — reported in dry-run issues instead of the row's content,
/// so a summary never leaks what was logged.
struct JefitRow: Sendable, Equatable {
    let line: Int
    let fields: [String]
}

/// One `### NAME ####…` … `######…` block of a Jefit export.
struct JefitSection: Sendable, Equatable {
    let name: String
    /// Column names from the section's first record. Empty for a section that
    /// carries no records at all (Jefit writes header-less empty sections).
    let header: [String]
    let rows: [JefitRow]

    /// The value of `column` in `row`, or nil when the column is absent or the
    /// row is short.
    func value(_ column: String, in row: JefitRow) -> String? {
        guard let index = header.firstIndex(of: column), index < row.fields.count else {
            return nil
        }
        return row.fields[index]
    }
}

/// Reader for Jefit's website export: one file, many CSV tables, each wrapped
/// in `### NAME ###…` / `######…` marker lines (#166).
///
/// Sections are split on whole lines first and only then parsed as CSV, so a
/// stray quote in one section (free-text NOTES are the likely culprit) cannot
/// swallow the sections after it. Within a section the parser is RFC 4180:
/// quoted fields may hold commas (`"225x6,235x6"`), doubled quotes and
/// newlines.
enum JefitCSV {

    static func sections(in text: String) -> [JefitSection] {
        var sections: [JefitSection] = []
        var currentName: String?
        var body: [(line: Int, text: Substring)] = []

        func close() {
            guard let name = currentName else { return }
            let records = records(from: body)
            let header = records.first?.fields ?? []
            sections.append(JefitSection(name: name, header: header, rows: Array(records.dropFirst())))
            currentName = nil
            body = []
        }

        var lineNumber = 0
        // "\r\n" is a single Character in Swift, so it must be named as a
        // separator in its own right — splitting on "\n" alone misses it.
        let lines = text.split(omittingEmptySubsequences: false) {
            $0 == "\n" || $0 == "\r\n" || $0 == "\r"
        }
        for line in lines {
            lineNumber += 1
            if line.hasPrefix("### ") {
                close()
                currentName = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
                continue
            }
            if isSectionEnd(line) {
                close()
                continue
            }
            if currentName != nil {
                body.append((lineNumber, line))
            }
        }
        close()
        return sections
    }

    /// A line made only of `#` (Jefit closes every section with one).
    private static func isSectionEnd(_ line: Substring) -> Bool {
        line.count >= 5 && line.allSatisfy { $0 == "#" }
    }

    /// Quote-aware record splitting over a section's lines. Works on UTF-8
    /// bytes: the structural characters are ASCII, so they can never be part
    /// of a multi-byte sequence, and byte scanning keeps a 1 MB export fast
    /// even in a debug build.
    static func records(from lines: [(line: Int, text: Substring)]) -> [JefitRow] {
        let quote = UInt8(ascii: "\"")
        let comma = UInt8(ascii: ",")
        let newline = UInt8(ascii: "\n")

        var rows: [JefitRow] = []
        var fields: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var recordOpen = false
        var startLine = 0

        func endField() {
            fields.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }

        for (lineNumber, text) in lines {
            if recordOpen {
                // Only reachable inside a quoted field that spans lines.
                field.append(newline)
            } else {
                if text.allSatisfy({ $0 == " " || $0 == "\t" }) { continue }
                recordOpen = true
                startLine = lineNumber
            }

            let bytes = Array(text.utf8)
            var index = 0
            while index < bytes.count {
                let byte = bytes[index]
                if inQuotes {
                    if byte == quote {
                        if index + 1 < bytes.count, bytes[index + 1] == quote {
                            field.append(quote)
                            index += 2
                            continue
                        }
                        inQuotes = false
                    } else {
                        field.append(byte)
                    }
                } else if byte == quote {
                    inQuotes = true
                } else if byte == comma {
                    endField()
                } else {
                    field.append(byte)
                }
                index += 1
            }

            if !inQuotes {
                endField()
                rows.append(JefitRow(line: startLine, fields: fields))
                fields = []
                recordOpen = false
            }
        }

        // An unterminated quote at the end of a section: keep what was read
        // rather than dropping it silently; the column-count check reports it.
        if recordOpen {
            endField()
            rows.append(JefitRow(line: startLine, fields: fields))
        }
        return rows
    }
}
