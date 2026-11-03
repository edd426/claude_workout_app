import SwiftUI

/// Filter chips for the library. Every chip is at least 44 pt tall (UI-T1),
/// and an active filter is a whole-chip Button that removes it, so its ✕ is
/// no longer a 12 pt target. Filters combine with the search query (#155).
struct FilterChipsView: View {
    let categories: [String]
    let categoryValues: [String: [String]]
    let activeFilters: [String: String]
    let onSelect: (String, String) -> Void
    let onRemove: (String) -> Void
    let onClearAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !activeFilters.isEmpty {
                    activeFilterChips
                    clearAllChip
                }
                ForEach(categories, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private static func display(_ raw: String) -> String {
        ExerciseLibraryViewModel.displayName(raw)
    }

    private var clearAllChip: some View {
        Button("Clear All") { onClearAll() }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(Color.primary)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .contentShape(Capsule())
            .accessibilityIdentifier("clearAllFilters")
    }

    private var activeFilterChips: some View {
        ForEach(activeFilters.sorted(by: { $0.key < $1.key }), id: \.key) { category, value in
            activeFilterChip(category: category, value: value)
        }
    }

    private func activeFilterChip(category: String, value: String) -> some View {
        let title = "\(Self.display(category)): \(Self.display(value))"
        return Button {
            onRemove(category)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(BrandTheme.accentText)
            .background(BrandTheme.accent.opacity(0.15), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove filter \(title)")
    }

    private func categoryChip(_ category: String) -> some View {
        let isActive = activeFilters[category] != nil
        return Menu {
            ForEach(categoryValues[category] ?? [], id: \.self) { value in
                Button(Self.display(value)) {
                    onSelect(category, value)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(Self.display(category))
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .foregroundStyle(isActive ? BrandTheme.accentText : Color.primary)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .contentShape(Capsule())
        }
    }
}
