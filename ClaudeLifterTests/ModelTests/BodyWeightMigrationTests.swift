import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

@Suite("BodyWeight Schema Migration Tests")
@MainActor
struct BodyWeightMigrationTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "bw-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("V1 store migrates to V2 with data intact and BodyWeightEntry usable")
    func v1StoreMigratesToV2() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")

        // Build a genuine V1 store (no migration plan, V1 schema only) and seed it.
        do {
            let v1Schema = Schema(versionedSchema: ClaudeLifterSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: storeURL)]
            )
            let context = v1Container.mainContext
            let exercise = Exercise(name: "Bench Press", isCustom: false)
            context.insert(exercise)
            let workout = Workout(name: "V1 Workout", startedAt: .now)
            context.insert(workout)
            let template = WorkoutTemplate(name: "V1 Template")
            context.insert(template)
            try context.save()
        }

        // Reopen through the factory: CurrentSchema is V2, so this exercises the
        // V1→V2 lightweight stage. Must open, not quarantine.
        let result = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )
        #expect(result.outcome == .opened)

        let context = result.container.mainContext

        // V1 data survived.
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "V1 Workout")
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.count == 1)

        // The V2 model works in the migrated store.
        let entry = BodyWeightEntry(weightKg: 84.3)
        context.insert(entry)
        try context.save()
        let entries = try context.fetch(FetchDescriptor<BodyWeightEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.weightKg == 84.3)
        #expect(entries.first?.syncStatus == .pending)
    }

    @Test("Migrated store re-opens under V2 without another migration")
    func migratedStoreReopensCleanly() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appending(path: "default.store")

        do {
            let v1Schema = Schema(versionedSchema: ClaudeLifterSchemaV1.self)
            let v1Container = try ModelContainer(
                for: v1Schema,
                configurations: [ModelConfiguration(schema: v1Schema, url: storeURL)]
            )
            let context = v1Container.mainContext
            context.insert(Workout(name: "Survivor", startedAt: .now))
            try context.save()
        }

        // First open migrates; write a weight entry.
        do {
            let first = try ModelContainerFactory.make(
                storeURL: storeURL,
                quarantineDirectory: dir.appending(path: "StoreQuarantine")
            )
            #expect(first.outcome == .opened)
            let context = first.container.mainContext
            context.insert(BodyWeightEntry(weightKg: 84.0, source: "manual"))
            try context.save()
        }

        // Second open: stable V2, everything still there.
        let second = try ModelContainerFactory.make(
            storeURL: storeURL,
            quarantineDirectory: dir.appending(path: "StoreQuarantine")
        )
        #expect(second.outcome == .opened)
        let context = second.container.mainContext
        #expect(try context.fetch(FetchDescriptor<Workout>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<BodyWeightEntry>()).count == 1)
    }
}
