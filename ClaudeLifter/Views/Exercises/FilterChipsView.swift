import SwiftUI

struct FilterChipsView: View {
    let categories: [String]
    let activeFilters: [String: String]
    let onSelect: (String, String) -> Void
    let onRemove: (String) -> Void
    let onClearAll: () -> Void

    private let categoryValues: [String: [String]] = [
        "muscle_group": ["chest", "back", "shoulders", "biceps", "triceps", "quadriceps", "hamstrings", "glutes", "calves", "abs"],
        "equipment": ["barbell", "dumbbell", "machine", "cable", "bodyweight", "kettlebell", "band"],
        "movement_pattern": ["horizontal_push", "horizontal_pull", "vertical_push", "vertical_pull", "hip_hinge", "squat"],
        "force": ["push", "pull", "static"],
        "mechanic": ["compound", "isolation"],
        "level": ["beginner", "intermediate", "advanced"]
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !activeFilters.isEmpty {
                    clearAllChip
                    activeFilterChips
                }
                ForEach(categories, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private var clearAllChip: some View {
        Button("Clear All") { onClearAll() }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .cornerRadius(16)
    }

    private var activeFilterChips: some View {
        ForEach(activeFilters.sorted(by: { $0.key < $1.key }), id: \.key) { category, value in
            activeFilterChip(category: category, value: value)
        }
    }

    private func activeFilterChip(category: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(category.replacingOccurrences(of: "_", with: " ").capitalized): \(value.replacingOccurrences(of: "_", with: " ").capitalized)")
                .font(.caption)
            Button {
                onRemove(category)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.2))
        .foregroundStyle(.blue)
        .cornerRadius(16)
    }

    private func categoryChip(_ category: String) -> some View {
        Menu(category.replacingOccurrences(of: "_", with: " ").capitalized) {
            ForEach(categoryValues[category] ?? [], id: \.self) { value in
                Button(value.replacingOccurrences(of: "_", with: " ").capitalized) {
                    onSelect(category, value)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(activeFilters[category] != nil ? Color.blue.opacity(0.1) : Color(uiColor: .secondarySystemBackground))
        .foregroundStyle(activeFilters[category] != nil ? .blue : .primary)
        .cornerRadius(16)
    }
}
