import Testing
import Foundation
@testable import ClaudeLifter

/// Small pure helpers behind the 1.9.0 workout cards.
@Suite("Workout card helpers")
@MainActor
struct WorkoutCardHelpersTests {

    // MARK: - #170 photo source

    @Test("His own machine photo wins over the catalog picture")
    func userPhotoWins() {
        let exercise = TestFixtures.makeExercise(name: "Seated Leg Curl")
        exercise.photoURL = "exercises/ext/Seated_Leg_Curl.jpg"
        exercise.imageURL = "https://example.com/Seated_Leg_Curl/0.jpg"

        #expect(ExercisePhotoSource(exercise: exercise) == .userPhoto("exercises/ext/Seated_Leg_Curl.jpg"))
    }

    @Test("Without a photo, the catalog's start image is used")
    func catalogImageFallback() throws {
        let exercise = TestFixtures.makeExercise(name: "Leg Press")
        exercise.imageURL = "https://example.com/Leg_Press/0.jpg"

        let url = try #require(URL(string: "https://example.com/Leg_Press/0.jpg"))
        #expect(ExercisePhotoSource(exercise: exercise) == .catalog(url))
    }

    @Test("With neither, there is no thumbnail")
    func noPicture() {
        let exercise = TestFixtures.makeExercise(name: "Custom Thing", isCustom: true)
        exercise.photoURL = ""
        #expect(ExercisePhotoSource(exercise: exercise) == nil)
    }

    // MARK: - Keyboard bar

    @Test("The focused field resolves to its set, for −2.5 / +2.5 and Log set")
    func entryLookup() async throws {
        let exercise = TestFixtures.makeExercise(name: "Squat")
        let workout = Workout(name: "Draft", startedAt: .now)
        let we = WorkoutExercise(order: 0, exercise: exercise)
        let first = WorkoutSet(order: 0, weight: 80, reps: 8)
        let second = WorkoutSet(order: 1, weight: 80, reps: 8)
        we.sets = [first, second]
        workout.exercises = [we]
        let vm = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: MockWorkoutRepository(),
            autoFillService: MockAutoFillService()
        )

        let entry = try #require(vm.entry(exerciseID: we.id, setID: second.id))
        #expect(entry.set.id == second.id)
        #expect(entry.workoutExercise.id == we.id)
        #expect(vm.entry(exerciseID: UUID(), setID: second.id) == nil)
    }
}
