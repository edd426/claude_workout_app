import Foundation

enum BuildInfo {
    /// Compile-time timestamp — changes every build, proving which binary is running
    static let buildTimestamp: String = {
        let date = Date()
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
