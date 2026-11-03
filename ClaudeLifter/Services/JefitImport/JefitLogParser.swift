import Foundation

/// One `weight x reps` entry of a Jefit `logs` string, in the unit that was
/// in force when it was logged. `index` is its position in the string,
/// counting malformed parts, so derived set ids stay stable.
struct JefitLoggedSet: Sendable, Equatable {
    let index: Int
    let weight: Double
    let reps: Int
}

struct JefitLogParseResult: Sendable, Equatable {
    var sets: [JefitLoggedSet] = []
    var malformedParts = 0
}

/// Parses EXERCISE LOGS `logs` values: `"225x6,235x6"`, `"59.9998x12"`,
/// `"0x15"` (bodyweight). Anything that is not plain digits, an `x`, and
/// plain digits is counted as malformed rather than guessed at — scientific
/// notation, negative numbers, fractional reps and extra `x` included.
enum JefitLogParser {

    static func parse(_ logs: String) -> JefitLogParseResult {
        var result = JefitLogParseResult()
        let trimmed = logs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return result }

        for (index, rawPart) in trimmed.split(separator: ",", omittingEmptySubsequences: false).enumerated() {
            if let set = parsePart(rawPart, index: index) {
                result.sets.append(set)
            } else {
                result.malformedParts += 1
            }
        }
        return result
    }

    private static func parsePart(_ rawPart: Substring, index: Int) -> JefitLoggedSet? {
        let part = rawPart.trimmingCharacters(in: .whitespaces).lowercased()
        let pieces = part.split(separator: "x", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              isDecimal(pieces[0]),
              isInteger(pieces[1]),
              let weight = Double(pieces[0]),
              let reps = Int(pieces[1]) else {
            return nil
        }
        return JefitLoggedSet(index: index, weight: weight, reps: reps)
    }

    private static func isInteger(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isASCIIDigit)
    }

    /// Digits with at most one interior decimal point: `225`, `59.9998`.
    private static func isDecimal(_ text: Substring) -> Bool {
        let halves = text.split(separator: ".", omittingEmptySubsequences: false)
        switch halves.count {
        case 1: return isInteger(halves[0])
        case 2: return isInteger(halves[0]) && isInteger(halves[1])
        default: return false
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
