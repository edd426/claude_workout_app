import SwiftUI

struct FilterChipsView: View {
    let categories: [String]
    let selectedCategory: String?
    let selectedValue: String?
    let onSelect: (String, String) -> Void
    let onClear: () -> Void

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
                if selectedCategory != nil {
                    clearChip
                }
                ForEach(categories, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private var clearChip: some View {
        Button("Clear") { onClear() }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.2))
            .foregroundStyle(.orange)
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
        .background(selectedCategory == category ? Color.blue.opacity(0.2) : Color(uiColor: .secondarySystemBackground))
        .foregroundStyle(selectedCategory == category ? .blue : .primary)
        .cornerRadius(16)
    }
}
