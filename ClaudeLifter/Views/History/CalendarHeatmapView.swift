import SwiftUI

struct CalendarHeatmapView: View {
    @Bindable var vm: CalendarViewModel

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            monthHeader
            dayLabelsRow
            daysGrid
            weekCountLabel
        }
        .padding(.horizontal)
        .task { await vm.loadMonth() }
    }

    private var monthHeader: some View {
        HStack {
            monthButton("Previous month", systemImage: "chevron.left", id: "calendarPreviousMonth") {
                vm.previousMonth()
            }
            Spacer()
            Text(monthYearTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            monthButton("Next month", systemImage: "chevron.right", id: "calendarNextMonth") {
                vm.nextMonth()
            }
        }
    }

    /// Labelled, so VoiceOver and UI tests can find them by name (UI-A1).
    private func monthButton(
        _ title: String,
        systemImage: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.headline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }

    /// Weekday initials in the locale's order: Monday first where the week
    /// starts on Monday.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var dayLabelsRow: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayButton(date)
                } else {
                    Color.clear
                        .frame(minHeight: 44)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// A Button with a full label (UI-A5, UI-T4): "Thursday 8 October,
    /// 1 workout, 12 sets".
    private func dayButton(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let isSelected = vm.selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return Button {
            Task { await vm.selectDate(date) }
        } label: {
            CalendarDayCellView(
                day: calendar.component(.day, from: date),
                intensity: vm.workoutDays[day] ?? .none,
                isToday: calendar.isDateInToday(date),
                isSelected: isSelected,
                isInMonth: calendar.isDate(date, equalTo: vm.currentMonth, toGranularity: .month)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CalendarViewModel.accessibilityLabel(for: date, summary: vm.daySummaries[day]))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekCountLabel: some View {
        Text("Workouts this week: \(vm.workoutsThisWeek)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthYearTitle: String {
        vm.currentMonth.formatted(.dateTime.month(.wide).year())
    }

    private var gridDays: [Date?] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: vm.currentMonth)
        ) else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leading)
        for dayOffset in 0..<daysInMonth {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) {
                days.append(date)
            }
        }
        // Pad to complete the last row
        let remainder = days.count % 7
        if remainder != 0 {
            days += Array(repeating: nil, count: 7 - remainder)
        }
        return days
    }
}
