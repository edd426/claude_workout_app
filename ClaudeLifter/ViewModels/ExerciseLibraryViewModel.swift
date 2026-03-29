import Foundation
import Observation

@Observable
@MainActor
final class ExerciseLibraryViewModel {
    var exercises: [Exercise] = []
    var searchQuery = ""
    var selectedCategory: String? = nil
    var selectedValue: String? = nil
    var isLoading = false
    var errorMessage: String? = nil

    let filterCategories = ["muscle_group", "equipment", "movement_pattern", "force", "mechanic", "level"]

    private let exerciseRepository: any ExerciseRepository

    init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    func loadExercises() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let category = selectedCategory, let value = selectedValue {
                exercises = try await exerciseRepository.filter(category: category, value: value)
            } else {
                exercises = try await exerciseRepository.fetchAll()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performSearch() async {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            await loadExercises()
            return
        }
        do {
            exercises = try await exerciseRepository.search(query: searchQuery)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectFilter(category: String, value: String) {
        selectedCategory = category
        selectedValue = value
    }

    func clearFilter() {
        selectedCategory = nil
        selectedValue = nil
    }
}
