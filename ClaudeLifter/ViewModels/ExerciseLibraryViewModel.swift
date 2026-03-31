import Foundation
import Observation

@Observable
@MainActor
final class ExerciseLibraryViewModel {
    var exercises: [Exercise] = []
    var searchQuery = ""
    var activeFilters: [String: String] = [:]
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
            if activeFilters.isEmpty {
                exercises = try await exerciseRepository.fetchAll()
            } else {
                var all = try await exerciseRepository.fetchAll()
                for (category, value) in activeFilters {
                    all = all.filter { exercise in
                        exercise.tags.contains { $0.category == category && $0.value == value }
                    }
                }
                exercises = all
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
        activeFilters[category] = value
    }

    func removeFilter(category: String) {
        activeFilters.removeValue(forKey: category)
    }

    func clearFilters() {
        activeFilters.removeAll()
    }
}
