import Foundation
import SwiftData

/// Creates the app's `ModelContainer` with a non-destructive recovery path.
///
/// Replaces the old behavior of deleting `default.store` on any open failure
/// (issue #72). A store that fails to open is moved — never deleted — into a
/// timestamped quarantine directory so the data can be recovered by a future
/// migration fix or manual inspection.
enum ModelContainerFactory {

    enum RecoveryOutcome: Equatable {
        /// Store opened normally (or was created fresh on first launch).
        case opened
        /// Store failed to open; files were quarantined and a fresh store created.
        case quarantined(to: URL)
    }

    /// The result of container creation, carrying what happened for the caller
    /// to surface (log, banner) instead of failing silently.
    struct Result {
        let container: ModelContainer
        let outcome: RecoveryOutcome
    }

    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    static var defaultQuarantineDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "StoreQuarantine")
    }

    /// Create the container at `storeURL`, migrating via `ClaudeLifterMigrationPlan`.
    /// On open failure, quarantine the store files and retry with a fresh store.
    /// `onQuarantine` receives the quarantine destination and runs BEFORE the
    /// fresh-store attempt, so the recovery location is recorded even if that
    /// second attempt also fails and the app aborts.
    static func make(
        storeURL: URL = defaultStoreURL,
        quarantineDirectory: URL = defaultQuarantineDirectory,
        onQuarantine: (URL) -> Void = { _ in }
    ) throws -> Result {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: ClaudeLifterMigrationPlan.self,
                configurations: [configuration]
            )
            return Result(container: container, outcome: .opened)
        } catch {
            let destination = try quarantine(
                storeURL: storeURL,
                into: quarantineDirectory,
                openError: error
            )
            onQuarantine(destination)
            let container = try ModelContainer(
                for: schema,
                migrationPlan: ClaudeLifterMigrationPlan.self,
                configurations: [configuration]
            )
            return Result(container: container, outcome: .quarantined(to: destination))
        }
    }

    /// Move `default.store`, `-wal`, and `-shm` into a timestamped subdirectory of
    /// `quarantineDirectory`, alongside a small text file recording the open error.
    private static func quarantine(
        storeURL: URL,
        into quarantineDirectory: URL,
        openError: Error
    ) throws -> URL {
        let fm = FileManager.default
        // UUID suffix: the timestamp alone has one-second granularity, and two
        // recovery attempts in the same second must not collide.
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
            + "-" + UUID().uuidString.prefix(8)
        let destination = quarantineDirectory.appending(path: String(stamp))
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        let storeName = storeURL.lastPathComponent
        let storeDirectory = storeURL.deletingLastPathComponent()
        for suffix in ["", "-wal", "-shm"] {
            let source = storeDirectory.appending(path: "\(storeName)\(suffix)")
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.moveItem(
                at: source,
                to: destination.appending(path: source.lastPathComponent)
            )
        }

        let report = """
        Store failed to open and was quarantined (not deleted) at \(stamp).
        Error: \(String(describing: openError))
        """
        try? report.write(
            to: destination.appending(path: "open-error.txt"),
            atomically: true,
            encoding: .utf8
        )
        return destination
    }
}
