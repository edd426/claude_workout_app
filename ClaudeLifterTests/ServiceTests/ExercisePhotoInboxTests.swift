import Foundation
import SwiftData
import Testing
@testable import ClaudeLifter

/// #170: the MCP attaches a gym-machine photo by enqueueing
/// `setExercisePhoto {externalId, blobPath}`; the phone applies it after
/// approval by pointing the exercise's `photoURL` at the blob.
@Suite("InboxApplier — setExercisePhoto (#170)")
@MainActor
struct ExercisePhotoInboxTests {

    @MainActor
    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let exercises: SwiftDataExerciseRepository
        let templates: SwiftDataTemplateRepository
        let applier: InboxApplier
        let bundled: Exercise
        let custom: Exercise

        static let customExternalId = "custom:belt-squat:7D3E1B6A-0C5F-4E2B-9A61-2B4C8D9E0F11"

        init() throws {
            container = try makeTestContainer()
            context = container.mainContext
            exercises = SwiftDataExerciseRepository(context: context)
            templates = SwiftDataTemplateRepository(context: context)
            applier = InboxApplier(
                templateRepository: templates,
                exerciseRepository: exercises,
                reportRepository: SwiftDataExerciseReportRepository(context: context),
                alternativeRepository: SwiftDataExerciseAlternativeRepository(context: context)
            )
            bundled = Exercise(name: "Leg Extensions", isCustom: false, externalId: "Leg_Extensions")
            custom = Exercise(name: "Belt Squat", isCustom: true, externalId: Self.customExternalId)
            context.insert(bundled)
            context.insert(custom)
            try context.save()
        }
    }

    private func operation(
        externalId: String,
        blobPath: String,
        status: String = "awaitingApproval",
        requiresApproval: Bool = true
    ) throws -> InboxOperationDTO {
        let payload = SetExercisePhotoPayload(externalId: externalId, blobPath: blobPath)
        let value = try JSONDecoder().decode(InboxJSONValue.self, from: JSONEncoder().encode(payload))
        return InboxOperationDTO(
            id: UUID().uuidString, createdAt: "2026-11-03T09:00:00.000Z", op: "setExercisePhoto",
            payload: value, requiresApproval: requiresApproval, status: status, appliedAt: nil, error: nil
        )
    }

    @Test("setExercisePhoto needs approval: a pending one waits rather than applying")
    func pendingAwaitsApproval() async throws {
        let env = try Env()

        let results = await env.applier.process([
            try operation(externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg", status: "pending")
        ])

        #expect(results.first?.status == .awaitingApproval)
        #expect(env.bundled.photoURL == nil)
    }

    @Test("Approving sets a bundled exercise's photoURL to the blob path")
    func approveBundled() async throws {
        let env = try Env()

        let result = await env.applier.approve(
            try operation(externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg")
        )

        #expect(result.status == .applied)
        #expect(env.bundled.photoURL == "exercises/ext/Leg_Extensions.jpg")
    }

    @Test("Approving sets a custom exercise's photoURL, matched by its custom: id")
    func approveCustom() async throws {
        let env = try Env()
        let path = "exercises/ext/\(Env.customExternalId).jpg"

        let result = await env.applier.approve(try operation(externalId: Env.customExternalId, blobPath: path))

        #expect(result.status == .applied)
        #expect(env.custom.photoURL == path)
    }

    @Test("An unknown externalId fails the op cleanly and changes nothing")
    func unknownExerciseFails() async throws {
        let env = try Env()

        let result = await env.applier.approve(
            try operation(externalId: "Not_In_Catalog", blobPath: "exercises/ext/Not_In_Catalog.jpg")
        )

        #expect(result.status == .failed)
        #expect(result.error?.contains("Not_In_Catalog") == true)
        #expect(env.bundled.photoURL == nil)
        #expect(env.custom.photoURL == nil)
    }

    @Test("A blobPath that is not exactly exercises/ext/{externalId}.jpg is rejected", arguments: [
        "exercises/ext/Squat.jpg",                  // another exercise's photo
        "exercises/Leg_Extensions.jpg",              // the old per-UUID family
        "reports/Leg_Extensions.jpg",                // another family
        "exercises/ext/Leg_Extensions.png",          // wrong extension
        "exercises/ext/../ext/Leg_Extensions.jpg",   // traversal
        "/exercises/ext/Leg_Extensions.jpg",         // absolute
        "",
    ])
    func mismatchedBlobPathRejected(blobPath: String) async throws {
        let env = try Env()
        env.bundled.photoURL = "exercise_photos/mine.jpg"

        let result = await env.applier.approve(try operation(externalId: "Leg_Extensions", blobPath: blobPath))

        #expect(result.status == .failed)
        #expect(env.bundled.photoURL == "exercise_photos/mine.jpg")
    }

    @Test("Declining leaves the photo untouched")
    func declineChangesNothing() async throws {
        let env = try Env()

        let result = env.applier.decline(
            try operation(externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg")
        )

        #expect(result.status == .rejected)
        #expect(env.bundled.photoURL == nil)
    }

    // MARK: - Approval preview

    @Test("The preview is one line naming the exercise: Set photo · Leg Extensions")
    func previewLine() async throws {
        let env = try Env()
        let builder = InboxChangePreviewBuilder(templateRepository: env.templates, exerciseRepository: env.exercises)

        let preview = await builder.preview(
            for: try operation(externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg")
        )

        #expect(preview.title == "Set photo · Leg Extensions")
        #expect(preview.lines.isEmpty)
        #expect(preview.isDestructive == false)
        #expect(preview.summary == "Adds a photo to the exercise card.")
    }

    @Test("The preview says when the exercise is missing, so the approval will fail")
    func previewUnknownExercise() async throws {
        let env = try Env()
        let builder = InboxChangePreviewBuilder(templateRepository: env.templates, exerciseRepository: env.exercises)

        let preview = await builder.preview(
            for: try operation(externalId: "Hack_Squat", blobPath: "exercises/ext/Hack_Squat.jpg")
        )

        #expect(preview.title == "Set photo · Hack Squat")
        #expect(preview.summary == "This exercise is not on this phone; approving it will fail.")
    }

    @Test("The preview says when the photo replaces one already attached")
    func previewReplaces() async throws {
        let env = try Env()
        env.bundled.photoURL = "exercise_photos/mine.jpg"
        let builder = InboxChangePreviewBuilder(templateRepository: env.templates, exerciseRepository: env.exercises)

        let preview = await builder.preview(
            for: try operation(externalId: "Leg_Extensions", blobPath: "exercises/ext/Leg_Extensions.jpg")
        )

        #expect(preview.summary == "Replaces the photo already on the exercise card.")
    }
}

/// Fetching blob photos into the local cache the exercise screens read.
/// Before #170 nothing downloaded exercise photos: every one was taken on
/// this phone and stored locally, so a blob path would never have shown.
@Suite("ExercisePhotoDownloader (#170)")
@MainActor
struct ExercisePhotoDownloaderTests {

    @MainActor
    final class MemoryCache: ExercisePhotoCaching {
        var stored: [String: Data] = [:]
        func hasPhoto(at relativePath: String) -> Bool { stored[relativePath] != nil }
        func store(_ data: Data, at relativePath: String) throws { stored[relativePath] = data }
    }

    private struct Env {
        let container: ModelContainer
        let context: ModelContext
        let images: MockImageUploadService
        let cache: MemoryCache
        let downloader: ExercisePhotoDownloader
    }

    private func makeEnv() throws -> Env {
        let container = try makeTestContainer()
        let images = MockImageUploadService()
        images.downloadResultData = Data([0xFF, 0xD8, 0xFF])
        let cache = MemoryCache()
        return Env(
            container: container,
            context: container.mainContext,
            images: images,
            cache: cache,
            downloader: ExercisePhotoDownloader(
                exerciseRepository: SwiftDataExerciseRepository(context: container.mainContext),
                imageService: images,
                cache: cache
            )
        )
    }

    @Test("A blob-path photo is downloaded through the existing SAS path and cached once")
    func fetchesOnce() async throws {
        let env = try makeEnv()
        let exercise = Exercise(name: "Leg Extensions", isCustom: false, externalId: "Leg_Extensions")
        exercise.photoURL = "exercises/ext/Leg_Extensions.jpg"
        env.context.insert(exercise)
        try env.context.save()

        #expect(await env.downloader.fetchMissing() == 1)
        #expect(env.images.lastDownloadedPath == "exercises/ext/Leg_Extensions.jpg")
        #expect(env.cache.stored["exercises/ext/Leg_Extensions.jpg"] == Data([0xFF, 0xD8, 0xFF]))

        #expect(await env.downloader.fetchMissing() == 0)
        #expect(env.images.downloadCallCount == 1)
    }

    @Test("A photo taken on this phone is already local and never downloaded")
    func localPhotosAreSkipped() async throws {
        let env = try makeEnv()
        let exercise = Exercise(name: "Bench", isCustom: false, externalId: "Bench")
        exercise.photoURL = "exercise_photos/\(exercise.id.uuidString).jpg"
        env.context.insert(exercise)
        try env.context.save()

        #expect(await env.downloader.fetchMissing() == 0)
        #expect(env.images.downloadCallCount == 0)
    }

    @Test("A failed download does not throw, and is retried next time")
    func failureRetriesLater() async throws {
        let env = try makeEnv()
        let exercise = Exercise(name: "Leg Extensions", isCustom: false, externalId: "Leg_Extensions")
        exercise.photoURL = "exercises/ext/Leg_Extensions.jpg"
        env.context.insert(exercise)
        try env.context.save()
        env.images.errorToThrow = SyncError.serverError(500)

        #expect(await env.downloader.fetchMissing() == 0)

        env.images.errorToThrow = nil
        #expect(await env.downloader.fetchMissing() == 1)
    }

    @Test("Only well-formed exercise blob paths count as downloadable", arguments: [
        ("exercises/ext/Leg_Extensions.jpg", true),
        ("exercises/7D3E1B6A-0C5F-4E2B-9A61-2B4C8D9E0F11.jpg", true),
        ("exercise_photos/7D3E1B6A.jpg", false),
        ("reports/7D3E1B6A.jpg", false),
        ("exercises/../reports/x.jpg", false),
        ("/exercises/ext/x.jpg", false),
        ("exercises/ext/x.png", false),
        ("", false),
    ])
    func blobPathRecognition(path: String, expected: Bool) {
        #expect(ExercisePhotoDownloader.isDownloadablePath(path) == expected)
    }
}
