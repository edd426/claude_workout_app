import SwiftUI

struct CalendarDayCellView: View {
    let day: Int
    let intensity: CalendarViewModel.WorkoutIntensity
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(cellBackground)
            if isToday && !isSelected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            Text("\(day)")
                .font(.system(size: 14, weight: isToday || isSelected ? .semibold : .regular))
                .foregroundStyle(labelColor)
        }
        .frame(width: 36, height: 36)
        .opacity(isInMonth ? 1.0 : 0.3)
    }

    private var cellBackground: Color {
        if isSelected {
            return .accentColor
        }
        switch intensity {
        case .none: return .clear
        case .light: return .accentColor.opacity(0.3)
        case .medium: return .accentColor.opacity(0.6)
        case .heavy: return .accentColor.opacity(1.0)
        }
    }

    private var labelColor: Color {
        if isSelected { return .white }
        if intensity == .heavy { return .white }
        return .primary
    }
}
