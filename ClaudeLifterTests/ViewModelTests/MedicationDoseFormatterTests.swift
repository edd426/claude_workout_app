import Foundation
import Testing
@testable import ClaudeLifter

@Suite("Medication dose formatting")
@MainActor
struct MedicationDoseFormatterTests {
    private let formatter = MedicationTestClock.formatter
    private let now = MedicationTestClock.now

    @Test("Amounts read naturally, singular for one", arguments: [
        (0.25, DoseUnit.mL, "0.25 mL"),
        (1.0, .tablet, "1 tablet"),
        (1.5, .tablet, "1.5 tablets"),
        (1.0, .syringeUnits, "1 unit"),
        (10.0, .syringeUnits, "10 units"),
        (250.0, .mcg, "250 mcg"),
        (400.0, .IU, "400 IU"),
        (0.125, .mL, "0.125 mL"),
    ])
    func amounts(amount: Double, unit: DoseUnit, expected: String) {
        #expect(formatter.amount(amount, unit: unit) == expected)
    }

    @Test("Volumes and tablets show their computed mg; masses and IU do not")
    func computedMgInBrackets() {
        #expect(formatter.amount(0.25, unit: .mL, computedMg: 2.5) == "0.25 mL (2.5 mg)")
        #expect(formatter.amount(2, unit: .tablet, computedMg: 100) == "2 tablets (100 mg)")
        #expect(formatter.amount(250, unit: .mcg, computedMg: 0.25) == "250 mcg")
        #expect(formatter.amount(0.25, unit: .mL, computedMg: nil) == "0.25 mL")
    }

    @Test("When reads today, yesterday, a weekday, then a date", arguments: [
        (0, 8, 5, "today 8:05"),
        (-1, 21, 10, "yesterday 21:10"),
        (-3, 21, 10, "Sun 21:10"),
        (-6, 7, 0, "Thu 7:00"),
        (-10, 21, 10, "25 Oct 21:10"),
    ])
    func when(offset: Int, hour: Int, minute: Int, expected: String) {
        #expect(formatter.when(MedicationTestClock.at(offset, hour, minute), now: now) == expected)
    }

    @Test("A dose from an earlier year shows the year, not a time")
    func earlierYear() {
        let date = MedicationTestClock.at(-397, 9, 0)
        #expect(formatter.when(date, now: now) == "3 Oct 2025")
    }

    @Test("The last-dose line: amount, mg, then when")
    func summary() {
        let medication = Medication(name: "Any", doseForm: .liquid, concentrationMgPerMl: 10)
        let dose = MedicationDose(
            logging: 0.25, unit: .mL, of: medication, takenAt: MedicationTestClock.at(-1, 21, 10)
        )
        #expect(formatter.summary(of: dose, now: now) == "0.25 mL (2.5 mg) · yesterday 21:10")
    }
}

@Suite("Body tab formatting helpers")
struct BodyFormatTests {
    @Test("Decimal entry accepts a point or a comma, and rejects junk", arguments: [
        ("84.3", 84.3 as Double?), ("84,3", 84.3), (" 7 ", 7), ("", nil), ("abc", nil), ("1.2.3", nil),
    ])
    func decimal(text: String, expected: Double?) {
        #expect(BodyFormat.decimal(text) == expected)
    }

    @Test("Age reads by calendar day", arguments: [
        (0, "today"), (1, "yesterday"), (2, "2 days ago"), (45, "45 days ago"), (90, "3 months ago"), (400, "over a year ago"),
    ])
    func age(daysAgo: Int, expected: String) {
        let date = TrendTestClock.day(-daysAgo)
        #expect(BodyFormat.age(of: date, now: TrendTestClock.now, calendar: TrendTestClock.calendar) == expected)
    }
}
