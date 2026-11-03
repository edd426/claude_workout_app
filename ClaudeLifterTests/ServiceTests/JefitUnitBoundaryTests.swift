import Testing
import Foundation
@testable import ClaudeLifter

@Suite("Jefit lb→kg boundary (#166)")
struct JefitUnitBoundaryTests {

    private let day: TimeInterval = 86_400

    /// Weekly sessions from a fixed origin, with an optional long break
    /// inserted before `gapBefore`.
    private func starts(_ count: Int, gapBefore: Int? = nil, gapDays: Double = 60) -> [Date] {
        var dates: [Date] = []
        var t: TimeInterval = 1_700_000_000
        for index in 0..<count {
            if index == gapBefore { t += gapDays * day }
            dates.append(Date(timeIntervalSince1970: t))
            t += 7 * day
        }
        return dates
    }

    private func observations(_ exercise: String, _ weights: [Double], from first: Int = 0) -> [JefitUnitObservation] {
        weights.enumerated().map {
            JefitUnitObservation(sessionIndex: first + $0.offset, exerciseKey: exercise, topWeight: $0.element)
        }
    }

    // MARK: - Set-log classification

    @Test("A set log equal to the logged weight is pounds; ×2.20462 is kilograms")
    func classifiesSetLogs() {
        #expect(JefitUnitBoundaryDetector.classify(loggedWeight: 225, weightLbs: 225) == .lbs)
        #expect(JefitUnitBoundaryDetector.classify(loggedWeight: 100, weightLbs: 220.462) == .kg)
        #expect(JefitUnitBoundaryDetector.classify(loggedWeight: 59.9998, weightLbs: 132.277) == .kg)
        #expect(JefitUnitBoundaryDetector.classify(loggedWeight: 100, weightLbs: 150) == nil)
        #expect(JefitUnitBoundaryDetector.classify(loggedWeight: 0, weightLbs: 0) == nil)
    }

    // MARK: - Detection

    @Test("Set-log evidence places the boundary at the first kilogram session")
    func detectsFromSetLogs() {
        let sessions = starts(4)
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: sessions,
            observations: observations("squat", [225, 235, 105, 107.5]),
            direct: [
                JefitDirectUnitEvidence(sessionIndex: 1, unit: .lbs),
                JefitDirectUnitEvidence(sessionIndex: 2, unit: .kg),
            ],
            currentUnitSetting: .kg
        )
        #expect(detection.boundary == .kilograms(from: sessions[2]))
        #expect(detection.evidence.poundSetLogs == 1)
        #expect(detection.evidence.kilogramSetLogs == 1)
        #expect(detection.evidence.contradictingSetLogs == 0)
    }

    @Test("Without set logs, weight continuity finds the switch (back squat 225 is lb, 105 is kg)")
    func detectsFromContinuity() {
        let sessions = starts(6, gapBefore: 3)
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: sessions,
            observations: observations("squat", [225, 230, 235, 105, 107.5, 110])
                + observations("curl", [40, 40, 45, 20, 20, 22]),
            direct: [],
            currentUnitSetting: .kg
        )
        #expect(detection.boundary == .kilograms(from: sessions[3]))
        #expect(detection.evidence.continuityJumps == 0)
    }

    @Test("A continuous history stays in one unit, chosen by the unit setting", arguments: [
        (WeightUnit.lbs, JefitUnitBoundary.allPounds),
        (WeightUnit.kg, JefitUnitBoundary.allKilograms),
    ])
    func noSwitch(setting: WeightUnit, expected: JefitUnitBoundary) {
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: starts(4),
            observations: observations("squat", [100, 102.5, 105, 107.5]),
            direct: [],
            currentUnitSetting: setting
        )
        #expect(detection.boundary == expected)
    }

    @Test("With no evidence at all, nothing is invented: everything stays in pounds")
    func noEvidence() {
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: starts(3),
            observations: [],
            direct: [],
            currentUnitSetting: nil
        )
        #expect(detection.boundary == .allPounds)
    }

    @Test("Undecided sessions between the last lb and first kg evidence follow the longest training break")
    func tieBreaksOnLongestGap() {
        // Sessions 1 and 2 carry no weights (bodyweight only); the move abroad
        // is the long break before session 2.
        let sessions = starts(4, gapBefore: 2, gapDays: 21)
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: sessions,
            observations: observations("squat", [225], from: 0) + observations("squat", [105], from: 3),
            direct: [
                JefitDirectUnitEvidence(sessionIndex: 0, unit: .lbs),
                JefitDirectUnitEvidence(sessionIndex: 3, unit: .kg),
            ],
            currentUnitSetting: .kg
        )
        #expect(detection.boundary == .kilograms(from: sessions[2]))
    }

    @Test("A stray contradicting set log is outvoted and reported")
    func contradictingEvidenceReported() {
        let sessions = starts(6)
        let direct = [0, 1, 2].map { JefitDirectUnitEvidence(sessionIndex: $0, unit: .lbs) }
            + [3, 4].map { JefitDirectUnitEvidence(sessionIndex: $0, unit: .kg) }
            + [JefitDirectUnitEvidence(sessionIndex: 5, unit: .lbs)]
        let detection = JefitUnitBoundaryDetector.detect(
            sessionStarts: sessions,
            observations: observations("squat", [225, 230, 235, 105, 107.5, 110]),
            direct: direct,
            currentUnitSetting: .kg
        )
        #expect(detection.boundary == .kilograms(from: sessions[3]))
        #expect(detection.evidence.contradictingSetLogs == 1)
    }

    // MARK: - Boundary semantics and conversion

    @Test("The boundary date itself is kilograms; earlier is pounds")
    func unitAtDate() {
        let switchDate = Date(timeIntervalSince1970: 1_750_000_000)
        let boundary = JefitUnitBoundary.kilograms(from: switchDate)
        #expect(boundary.unit(at: switchDate.addingTimeInterval(-1)) == .lbs)
        #expect(boundary.unit(at: switchDate) == .kg)
        #expect(JefitUnitBoundary.allPounds.unit(at: switchDate) == .lbs)
        #expect(JefitUnitBoundary.allKilograms.unit(at: switchDate) == .kg)
    }

    @Test("Logged weights convert to kilograms, rounded to 0.01", arguments: [
        (225.0, WeightUnit.lbs, 102.06),
        (45.0, WeightUnit.lbs, 20.41),
        (59.9998, WeightUnit.kg, 60.0),
        (102.5, WeightUnit.kg, 102.5),
    ])
    func convertsToKilograms(logged: Double, unit: WeightUnit, expected: Double) {
        #expect(JefitConverter.kilograms(fromLogged: logged, unit: unit) == expected)
    }

    @Test("A logged weight of 0 is bodyweight: nil")
    func zeroIsBodyweight() {
        #expect(JefitConverter.kilograms(fromLogged: 0, unit: .lbs) == nil)
        #expect(JefitConverter.kilograms(fromLogged: 0, unit: .kg) == nil)
    }
}
