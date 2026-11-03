import Testing
import Foundation
@testable import ClaudeLifter

@Suite("Jefit exercise mapping (#166)")
struct JefitExerciseMappingTests {

    private let squat = JefitLocalExercise(id: UUID(), name: "Barbell Squat", externalId: "Barbell_Squat", isCustom: false)
    private let bench = JefitLocalExercise(
        id: UUID(), name: "Barbell Bench Press - Medium Grip",
        externalId: "Barbell_Bench_Press_-_Medium_Grip", isCustom: false
    )
    private let curls = JefitLocalExercise(id: UUID(), name: "Hammer Curls", externalId: "Hammer_Curls", isCustom: false)
    private let singleLegPress = JefitLocalExercise(
        id: UUID(), name: "Single-Leg Press",
        externalId: "custom:single-leg-press:00000000-0000-0000-0000-000000000001", isCustom: true
    )

    private func table(
        catalog: [String: String] = [:],
        custom: [String: String] = [:]
    ) -> JefitExerciseMapTable {
        JefitExerciseMapTable(version: 1, catalog: catalog, custom: custom)
    }

    @Test("An exact catalog name wins, ignoring case and stray spaces")
    func exactMatch() {
        let mapper = JefitExerciseMapper(table: table(), localExercises: [squat])
        let resolution = mapper.resolve(" barbell squat ")
        #expect(resolution.target == .existing(squat))
        #expect(resolution.method == .exact)
    }

    @Test("The reviewed table maps a Jefit name to a catalog externalId")
    func tableCatalog() {
        let mapper = JefitExerciseMapper(
            table: table(catalog: ["Barbell Bench Press": "Barbell_Bench_Press_-_Medium_Grip"]),
            localExercises: [squat, bench]
        )
        let resolution = mapper.resolve("Barbell Bench Press")
        #expect(resolution.target == .existing(bench))
        #expect(resolution.method == .table)
    }

    @Test("A table custom entry reuses the phone's existing custom exercise of that name")
    func tableCustomReusesExisting() {
        let mapper = JefitExerciseMapper(
            table: table(custom: ["Machine Single-Leg Press": "Single-Leg Press"]),
            localExercises: [squat, singleLegPress]
        )
        let resolution = mapper.resolve("Machine Single-Leg Press ")
        #expect(resolution.target == .existing(singleLegPress))
        #expect(resolution.method == .table)
    }

    @Test("A table custom entry without a local match becomes a new custom under the canonical name")
    func tableCustomCreatesNew() {
        let mapper = JefitExerciseMapper(
            table: table(custom: ["One-Legged Press": "Single-Leg Press"]),
            localExercises: [squat]
        )
        let resolution = mapper.resolve("One-Legged Press")
        #expect(resolution.target == .newCustom(name: "Single-Leg Press"))
        #expect(resolution.method == .table)
    }

    @Test("Normalised matching ignores word order, punctuation and plurals", arguments: [
        "Squat, Barbell",
        "Barbell Squats",
        "squat - barbell",
    ])
    func normalisedMatch(name: String) {
        let mapper = JefitExerciseMapper(table: table(), localExercises: [squat, bench, curls])
        let resolution = mapper.resolve(name)
        #expect(resolution.target == .existing(squat))
        #expect(resolution.method == .normalized)
    }

    @Test("Normalised keys are order- and plural-insensitive")
    func normalisedKeys() {
        let key = JefitExerciseMapper.normalizedKey
        #expect(key("Bench Press - Barbell") == key("Barbell Bench Presses"))
        #expect(key("Dumbbell Hammer Curls") == key("dumbbell hammer curl"))
        #expect(key("Farmer's Walk") == key("Farmers Walk"))
        #expect(key("Pull Ups") == key("Pull-Up"))
        #expect(key("Leg Press") != key("Leg Extension"))
    }

    @Test("A table entry outranks a normalised guess")
    func tableBeatsNormalised() {
        // "Leg Curl Machine" would normalise onto a local "Machine Leg Curl";
        // the reviewed table says it is a different movement.
        let machineLegCurl = JefitLocalExercise(id: UUID(), name: "Machine Leg Curl", externalId: "X", isCustom: false)
        let mapper = JefitExerciseMapper(
            table: table(custom: ["Leg Curl Machine": "Leg Curl Machine"]),
            localExercises: [machineLegCurl]
        )
        #expect(mapper.resolve("Leg Curl Machine").target == .newCustom(name: "Leg Curl Machine"))
    }

    @Test("An unmapped name becomes a custom exercise under its Jefit name, never a drop")
    func unmappedBecomesCustom() {
        let mapper = JefitExerciseMapper(table: table(), localExercises: [squat, bench])
        let resolution = mapper.resolve("Zorbo Press ")
        #expect(resolution.target == .newCustom(name: "Zorbo Press"))
        #expect(resolution.method == .unmapped)
    }

    @Test("A table catalog id missing on this phone falls back instead of failing")
    func missingCatalogTargetFallsBack() {
        let mapper = JefitExerciseMapper(
            table: table(catalog: ["Zorbo Press": "Not_In_This_Store"]),
            localExercises: [squat]
        )
        #expect(mapper.resolve("Zorbo Press").target == .newCustom(name: "Zorbo Press"))
    }

    // MARK: - Custom exercise identity

    @Test("New custom exercises get deterministic ids and a custom: externalId")
    func customIdentity() {
        let first = JefitConverter.customExerciseIdentity(name: "Zorbo Press")
        let second = JefitConverter.customExerciseIdentity(name: "zorbo  press")
        #expect(first.id == second.id)
        #expect(first.externalId == "custom:zorbo-press:\(first.id.uuidString.lowercased())")
    }

    @Test("Custom slugs follow the server's grammar", arguments: [
        ("Barbell 1/2 Squat", "barbell-1-2-squat"),
        ("Crème Brûlée Curl!", "creme-brulee-curl"),
        ("!!!", "exercise"),
    ])
    func slugs(name: String, slug: String) {
        #expect(JefitConverter.customSlug(name) == slug)
    }

    // MARK: - The checked-in table

    @Test("The bundled mapping table loads")
    func bundledTableLoads() throws {
        let table = try JefitExerciseMapTable.bundled()
        #expect(table.version == 1)
        #expect(table.catalog.count > 100)
        #expect(!table.custom.isEmpty)
    }

    @Test("Every catalog target in the table exists in exercises.json")
    func everyTargetExists() throws {
        let table = try JefitExerciseMapTable.bundled()
        let url = try #require(Bundle.main.url(forResource: "exercises", withExtension: "json"))
        struct CatalogEntry: Decodable { let id: String }
        let ids = Set(try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url)).map(\.id))
        let missing = table.catalog.values.filter { !ids.contains($0) }
        #expect(missing.isEmpty, "Unknown externalIds: \(missing.sorted())")
    }

    @Test("No Jefit name is in both halves of the table, and no custom name is blank")
    func tableIsConsistent() throws {
        let table = try JefitExerciseMapTable.bundled()
        let catalogKeys = Set(table.catalog.keys.map { $0.lowercased() })
        let customKeys = Set(table.custom.keys.map { $0.lowercased() })
        #expect(catalogKeys.isDisjoint(with: customKeys))
        #expect(table.custom.values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}
