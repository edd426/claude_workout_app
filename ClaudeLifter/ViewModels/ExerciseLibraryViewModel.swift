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
    var filterCategories: [String] = []
    var categoryValues: [String: [String]] = [:]
    var totalCount = 0

    private let exerciseRepository: any ExerciseRepository
    private let pageSize = 50
    private var currentOffset = 0

    init(exerciseRepository: any ExerciseRepository) {
        self.exerciseRepository = exerciseRepository
    }

    func loadFilterOptions() async {
        do {
            filterCategories = try await exerciseRepository.fetchDistinctTagCategories()
            for cat in filterCategories {
                categoryValues[cat] = try await exerciseRepository.fetchDistinctTagValues(for: cat)
            }
        } catch {}
    }

    func loadExercises() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        defer { isLoading = false }
        do {
            if activeFilters.isEmpty {
                exercises = try await exerciseRepository.fetchPage(offset: 0, limit: pageSize)
                totalCount = try await exerciseRepository.fetchCount()
            } else {
                let filters = Array(activeFilters)
                // Use repository filter for first filter, then apply remaining in-memory
                var result = try await exerciseRepository.filter(category: filters[0].key, value: filters[0].value)
                for (category, value) in filters.dropFirst() {
                    result = result.filter { exercise in
                        exercise.tags.contains { $0.category == category && $0.value == value }
                    }
                }
                exercises = result
                totalCount = result.count
            }
            currentOffset = exercises.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard activeFilters.isEmpty, currentOffset < totalCount else { return }
        do {
            let page = try await exerciseRepository.fetchPage(offset: currentOffset, limit: pageSize)
            exercises.append(contentsOf: page)
            currentOffset = exercises.count
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
