import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("ModelContainerFactory Tests")
@MainActor
struct ModelContainerFactoryTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "factory-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Fresh store opens without quarantine")
    func freshStoreOpens() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try ModelContainerFactory.make(
            storeURL: dir.appending(path: "default.store"),
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )

        #expect(result.outcome == .opened)

        let context = result.container.mainContext
        context.insert(Workout(name: "Fresh", startedAt: .now))
        try context.save()
    }

    @Test("Existing store re-opens with data intact")
    func existingStoreReopens() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")
        let quarantine = dir.appending(path: "StoreQuarantine")

        // First open: write a workout.
        do {
            let first = try ModelContainerFactory.make(
                storeURL: storeURL, quarantineDirectory: quarantine
            )
            let context = first.container.mainContext
            context.insert(Workout(name: "Persisted", startedAt: .now))
            try context.save()
        }

        // Second open: same store, data must survive, no quarantine.
        let second = try ModelContainerFactory.make(
            storeURL: storeURL, quarantineDirectory: quarantine
        )
        #expect(second.outcome == .opened)
        let workouts = try second.container.mainContext.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "Persisted")
    }

    @Test("Corrupt store is quarantined, not deleted")
    func corruptStoreQuarantined() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")
        let quarantine = dir.appending(path: "StoreQuarantine")

        // A file of garbage bytes is not a SQLite database — open must fail.
        try Data("this is not a database".utf8).write(to: storeURL)
        var hookDestination: URL?

        let result = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: quarantine,
            onQuarantine: { hookDestination = $0 }
        )

        guard case .quarantined(let destination) = result.outcome else {
            Issue.record("Expected quarantine, got \(result.outcome)")
            return
        }
        // The hook must receive the real destination — it records the recovery
        // location BEFORE the fresh-store attempt, so it can't be wrong.
        #expect(hookDestination == destination)

        // The bytes were moved, not deleted.
        let quarantinedStore = destination.appending(path: "default.store")
        let moved = try Data(contentsOf: quarantinedStore)
        #expect(String(decoding: moved, as: UTF8.self) == "this is not a database")

        // An error report sits alongside the quarantined files.
        let report = destination.appending(path: "open-error.txt")
        #expect(FileManager.default.fileExists(atPath: report.path))

        // And the fresh replacement store is usable.
        let context = result.container.mainContext
        context.insert(Workout(name: "After recovery", startedAt: .now))
        try context.save()
    }

    @Test("Real device store opens non-destructively under the versioned schema")
    func realDeviceStoreOpens() throws {
        // Uses a local copy of the actual on-device store (never committed — it
        // holds personal data and the repo is public). Point the runner at it with:
        //   xcodebuild test ... TEST_RUNNER_CLAUDELIFTER_STORE_BACKUP_DIR=<dir>
        // Skips when unset so the suite stays green on other machines.
        guard let backupPath = ProcessInfo.processInfo
            .environment["CLAUDELIFTER_STORE_BACKUP_DIR"] else { return }
        let backupDir = URL(fileURLWithPath: backupPath)
        guard FileManager.default.fileExists(
            atPath: backupDir.appending(path: "default.store").path
        ) else { return }

        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for suffix in ["", "-shm", "-wal"] {
            let name = "default.store\(suffix)"
            try FileManager.default.copyItem(
                at: backupDir.appending(path: name),
                to: dir.appending(path: name)
            )
        }

        let result = try ModelContainerFactory.make(
            storeURL: dir.appending(path: "default.store"),
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )

        // The legacy (unversioned) store must open under the V1 versioned schema
        // without triggering recovery — this is the on-device safety guarantee.
        #expect(result.outcome == .opened)

        let context = result.container.mainContext
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        #expect(workouts.count >= 1)
        #expect(templates.count >= 3)
        #expect(exercises.count > 800)
    }
}
