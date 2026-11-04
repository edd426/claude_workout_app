import SwiftUI

/// One day of the heatmap. The calendar wraps it in a Button with the full
/// label, so this is only the drawing.
struct CalendarDayCellView: View {
    let day: Int
    let intensity: CalendarViewModel.WorkoutIntensity
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool

    var body: some View {
        Text("\(day)")
            .font(.subheadline.weight(isToday || isSelected ? .semibold : .regular))
            .monospacedDigit()
            // Seven columns can't hold AX5 digits: "10" wrapped to "1 / 0".
            // Shrink to fit the cell rather than break the number (UI-A3).
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Circle()
                    .fill(cellBackground)
                    .overlay { ring }
                    .padding(2)
            }
            .contentShape(Rectangle())
            .opacity(isInMonth ? 1.0 : 0.3)
    }

    /// Selected: a primary ring. Today: an accent ring. Colour is never the
    /// only signal; the button label carries the counts (UI-C4).
    @ViewBuilder
    private var ring: some View {
        if isSelected {
            Circle().strokeBorder(Color.primary, lineWidth: 2)
        } else if isToday {
            Circle().strokeBorder(BrandTheme.accent, lineWidth: 1.5)
        }
    }

    private var cellBackground: Color {
        switch intensity {
        case .none: return .clear
        case .light: return BrandTheme.accent.opacity(0.3)
        case .medium: return BrandTheme.accent.opacity(0.6)
        case .heavy: return BrandTheme.accent
        }
    }

    /// White on the full accent fill is 3.1:1; the dark palette colour is
    /// 5.9:1 in either appearance (UI-C3).
    private var labelColor: Color {
        intensity == .heavy ? BrandTheme.dark : .primary
    }
}
