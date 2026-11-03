import Foundation
import Observation

/// What the Measurements card shows for waist-to-height (#165).
enum WaistToHeightDisplay: Equatable, Sendable {
    /// No height on file: the card asks for it instead of showing a number.
    case needsHeight
    /// Height on file, no waist yet.
    case needsWaist
    /// `ratio` is truncated to two decimals for display, so a value never
    /// reads as a band it is not in (0.4996 shows 0.49, not 0.50).
    case ratio(Double, WaistToHeightBand)

    /// "WHtR 0.51 · aim below 0.5". The 0.5 line is NICE NG246's.
    var text: String {
        switch self {
        case .needsHeight: return "Add your height"
        case .needsWaist: return "Log your waist to see it"
        case .ratio(let value, let band):
            let shown = value.formatted(.number.precision(.fractionLength(2)))
            return band == .healthy
                ? "WHtR \(shown) · below 0.5"
                : "WHtR \(shown) · aim below 0.5"
        }
    }

    /// The NG246 band in words, nil until there is a ratio.
    var bandText: String? {
        guard case .ratio(_, let band) = self else { return nil }
        switch band {
        case .healthy: return "Healthy range (under 0.5)"
        case .increased: return "Increased risk (0.5 to 0.59)"
        case .high: return "High risk (0.6 or more)"
        }
    }
}

/// One point on the waist sparkline: a calendar month's mean.
struct MeasurementChartPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let valueCm: Double
    var id: Date { date }
}

/// Drives the Measurements card and its two sheets (#165): the latest waist,
/// waist-to-height against NICE NG246's 0.5 line, a monthly sparkline, the
/// waist log and the one-time height entry.
@Observable
@MainActor
final class MeasurementsViewModel {
    static let heightStyleKey = "heightDisplayStyle"
    /// Accepted waist entries, in cm.
    static let waistRangeCm: ClosedRange<Double> = 40...250
    static let sparklineMonths = 12

    private let repository: any BodyMeasurementRepository
    private let settings: SettingsManager
    private let preferences: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    /// Waist entries, oldest first.
    private(set) var waistHistory: [BodyMeasurement] = []
    private(set) var isLoaded = false
    /// The history could not be read: the card shows it with Retry.
    private(set) var loadError: String?
    /// The last waist entry failed: the sheet shows it and stays open.
    private(set) var entryError: String?

    init(
        repository: any BodyMeasurementRepository,
        settings: SettingsManager,
        preferences: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        self.repository = repository
        self.settings = settings
        self.preferences = preferences
        self.calendar = calendar
        self.now = now
        self.heightStyle = preferences.string(forKey: Self.heightStyleKey)
            .flatMap(HeightStyle.init(rawValue:))
            ?? HeightStyle.defaultStyle(for: settings.weightUnit)
    }

    func load() async {
        do {
            waistHistory = try await repository.fetch(site: .waist).reversed()
            loadError = nil
        } catch {
            loadError = "Couldn't load your measurements."
        }
        isLoaded = true
    }

    // MARK: - Waist

    var latestWaist: BodyMeasurement? { waistHistory.last }

    /// "92.5 cm".
    var latestWaistText: String? {
        latestWaist.map { "\(BodyFormat.number($0.valueCm, maxFractionDigits: 1)) cm" }
    }

    /// "12 days ago".
    var latestWaistAge: String? {
        latestWaist.map { BodyFormat.age(of: $0.recordedAt, now: now(), calendar: calendar) }
    }

    /// The waist sheet's starting value: the last entry, in cm.
    var waistPrefill: String {
        latestWaist.map { BodyFormat.number($0.valueCm, maxFractionDigits: 1) } ?? ""
    }

    /// A typed waist, or nil when it is not a plausible circumference.
    static func parseWaist(_ text: String) -> Double? {
        guard let value = BodyFormat.decimal(text), waistRangeCm.contains(value) else { return nil }
        return value
    }

    /// Saves a waist measurement taken now. False, with `entryError` set,
    /// when the value is out of range or the save fails.
    @discardableResult
    func logWaist(cm: Double) async -> Bool {
        guard Self.waistRangeCm.contains(cm) else {
            entryError = "Enter a waist between 40 and 250 cm."
            return false
        }
        let rounded = (cm * 10).rounded() / 10
        do {
            try await repository.save(
                BodyMeasurement(site: .waist, valueCm: rounded, recordedAt: now())
            )
        } catch {
            entryError = "Couldn't save that measurement. Try again."
            return false
        }
        entryError = nil
        await load()
        return true
    }

    func clearEntryError() {
        entryError = nil
    }

    // MARK: - Waist-to-height

    var waistToHeight: WaistToHeightDisplay {
        guard let height = settings.heightCm else { return .needsHeight }
        guard let waist = latestWaist?.valueCm,
              let ratio = BodyMetrics.waistToHeightRatio(waistCm: waist, heightCm: height) else {
            return .needsWaist
        }
        // Clean floating-point noise first (as BodyMetrics.band does), then
        // truncate, so the number shown never contradicts the band.
        let clean = (ratio * 1_000_000).rounded() / 1_000_000
        let shown = (clean * 100).rounded(.down) / 100
        return .ratio(shown, BodyMetrics.band(forWaistToHeightRatio: ratio))
    }

    // MARK: - Sparkline

    /// Monthly means of the last `sparklineMonths` months, oldest first.
    var waistSparkline: [MeasurementChartPoint] {
        guard let start = calendar.date(
            byAdding: .month, value: -(Self.sparklineMonths - 1),
            to: startOfMonth(now())
        ) else { return [] }
        var sums: [Date: (total: Double, count: Int)] = [:]
        for entry in waistHistory where entry.recordedAt >= start {
            let month = startOfMonth(entry.recordedAt)
            let current = sums[month] ?? (0, 0)
            sums[month] = (current.total + entry.valueCm, current.count + 1)
        }
        return sums
            .map { MeasurementChartPoint(date: $0.key, valueCm: $0.value.total / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    /// VoiceOver summary for the sparkline (UI-A4).
    var sparklineSummary: String {
        let points = waistSparkline
        guard let first = points.first, let last = points.last else {
            return "No waist measurements in the last year"
        }
        let format = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
            .month(.wide).year()
        let firstText = "\(BodyFormat.number(first.valueCm, maxFractionDigits: 1)) cm in \(first.date.formatted(format))"
        guard points.count > 1 else { return "Waist by month: \(firstText)" }
        let lastText = "\(BodyFormat.number(last.valueCm, maxFractionDigits: 1)) cm in \(last.date.formatted(format))"
        return "Waist by month, \(points.count) months: \(firstText), latest \(lastText)"
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    // MARK: - Height

    /// The user's preferred style, remembered from the last height entry.
    var heightStyle: HeightStyle {
        didSet { preferences.set(heightStyle.rawValue, forKey: Self.heightStyleKey) }
    }

    var heightCm: Double? { settings.heightCm }

    /// "5 ft 11 in" or "180 cm"; nil until a height is set.
    var heightText: String? {
        settings.heightCm.map { HeightEntry.text(cm: $0, style: heightStyle) }
    }

    /// Stores a height entered in feet and inches. False when unusable.
    @discardableResult
    func setHeight(feetText: String, inchesText: String) -> Bool {
        guard let cm = HeightEntry.cm(feetText: feetText, inchesText: inchesText) else { return false }
        settings.heightCm = cm
        heightStyle = .feetInches
        return true
    }

    /// Stores a height entered in centimetres. False when unusable.
    @discardableResult
    func setHeight(centimetresText: String) -> Bool {
        guard let cm = HeightEntry.cm(centimetresText: centimetresText) else { return false }
        settings.heightCm = cm
        heightStyle = .centimetres
        return true
    }
}
