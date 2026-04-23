import Foundation

enum BuildInfo {
    /// Timestamp the binary was actually built. Derived from the main
    /// executable's modification time, which is set by the linker at build
    /// time and is preserved through codesign. This is stable across app
    /// launches and gives us a truthful "when was this binary produced"
    /// value — the old implementation used `Date()` at first access which
    /// was actually LAUNCH time, misleading users into thinking a stale
    /// binary had just been built.
    static let buildDate: Date? = {
        guard let path = Bundle.main.executablePath else { return nil }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }()

    static let buildTimestamp: String = {
        guard let date = buildDate else { return "unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }()

    static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }()

    static let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }()

    static var summary: String {
        "ClaudeLifter v\(appVersion) (build \(buildNumber)) | Built: \(buildTimestamp)"
    }
}
