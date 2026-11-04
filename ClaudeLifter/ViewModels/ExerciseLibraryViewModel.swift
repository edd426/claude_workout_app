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

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a query or a filter narrows the list, so it isn't paged.
    var isNarrowed: Bool {
        !trimmedQuery.isEmpty || !activeFilters.isEmpty
    }

    /// "“row” · Equipment: Machine": what the list is narrowed by, for the
    /// result count and the empty state.
    var criteriaDescription: String {
        var parts: [String] = []
        if !trimmedQuery.isEmpty { parts.append("“\(trimmedQuery)”") }
        for (category, value) in activeFilters.sorted(by: { $0.key < $1.key }) {
            parts.append("\(Self.displayName(category)): \(Self.displayName(value))")
        }
        return parts.joined(separator: " · ")
    }

    /// "muscle_group" → "Muscle Group".
    static func displayName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func loadFilterOptions() async {
        do {
            filterCategories = try await exerciseRepository.fetchDistinctTagCategories()
            for cat in filterCategories {
                categoryValues[cat] = try await exerciseRepository.fetchDistinctTagValues(for: cat)
            }
        } catch {
            // Filters failing to load degrades the UI (chips disappear) without
            // obvious user feedback — surface it so we notice in logs/crash
            // reports instead of silently rendering an empty filter bar.
            print("⚠️ ExerciseLibraryViewModel.loadFilterOptions failed: \(error)")
            errorMessage = "Could not load filter options."
        }
    }

    /// Loads the list for the current query **and** filters (#155). Each
    /// narrows the other; neither replaces the other. With neither, the
    /// whole library loads a page at a time.
    func loadExercises() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        defer { isLoading = false }
        do {
            if isNarrowed {
                exercises = try await narrowedExercises()
                totalCount = exercises.count
            } else {
                exercises = try await exerciseRepository.fetchPage(offset: 0, limit: pageSize)
                totalCount = try await exerciseRepository.fetchCount()
            }
            currentOffset = exercises.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isNarrowed, currentOffset < totalCount else { return }
        do {
            let page = try await exerciseRepository.fetchPage(offset: currentOffset, limit: pageSize)
            exercises.append(contentsOf: page)
            currentOffset = exercises.count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Runs when the query changes. The filters stay applied.
    func performSearch() async {
        await loadExercises()
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

    /// Filters first when there are any (the repository narrows by one tag,
    /// the rest apply in memory), then the query. With only a query, the
    /// repository's substring search on its longest word gives the
    /// candidates and word-start matching trims them: "row" must not find
    /// "Throw".
    private func narrowedExercises() async throws -> [Exercise] {
        let query = trimmedQuery
        var result: [Exercise]
        let filters = activeFilters.sorted { $0.key < $1.key }
        if let first = filters.first {
            result = try await exerciseRepository.filter(category: first.key, value: first.value)
            for (category, value) in filters.dropFirst() {
                result = result.filter { exercise in
                    exercise.tags.contains { $0.category == category && $0.value == value }
                }
            }
        } else {
            result = try await searchCandidates(for: query)
        }
        guard !query.isEmpty else { return result }
        return result.filter { ExerciseSearch.matches(name: $0.name, query: query) }
    }

    /// A superset of the word-start matches. "pullup" is no substring of
    /// "Pull-Up", so a word with no substring hit retries on its first three
    /// letters.
    private func searchCandidates(for query: String) async throws -> [Exercise] {
        let longest = ExerciseSearch.words(query).max { $0.count < $1.count } ?? query
        let hits = try await exerciseRepository.search(query: longest)
        guard hits.isEmpty, longest.count > 3 else { return hits }
        return try await exerciseRepository.search(query: String(longest.prefix(3)))
    }
}

/// Word-start search for exercise names (#155).
///
/// Every word of the query has to begin a word of the name, so "row" finds
/// "Seated Cable Rows" and "Upright Row" but not "Medicine Ball Throw".
/// Words may run together across the name's separators, so "pullup" finds
/// "Pull-Up". Case and accents are ignored; word order is not required.
enum ExerciseSearch {
    static func matches(name: String, query: String) -> Bool {
        let nameWords = words(name)
        return words(query).allSatisfy { token in
            nameWords.indices.contains { start in
                nameWords[start...].joined().hasPrefix(token)
            }
        }
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
