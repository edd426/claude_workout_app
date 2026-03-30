import SwiftUI

struct CalendarHeatmapView: View {
    @Bindable var vm: CalendarViewModel

    private let calendar = Calendar.current
    private let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]
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
            Button {
                vm.previousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(monthYearTitle)
                .font(.headline)
            Spacer()
            Button {
                vm.nextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var dayLabelsRow: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(dayLabels.indices, id: \.self) { i in
                Text(dayLabels[i])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var daysGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridDays, id: \.self) { date in
                if let date {
                    let day = calendar.component(.day, from: date)
                    let isInMonth = calendar.isDate(date, equalTo: vm.currentMonth, toGranularity: .month)
                    let normalizedDay = calendar.startOfDay(for: date)
                    let intensity = vm.workoutDays[normalizedDay] ?? .none
                    let isToday = calendar.isDateInToday(date)
                    let isSelected = vm.selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false

                    CalendarDayCellView(
                        day: day,
                        intensity: intensity,
                        isToday: isToday,
                        isSelected: isSelected,
                        isInMonth: isInMonth
                    )
                    .onTapGesture {
                        Task { await vm.selectDate(date) }
                    }
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
            }
        }
    }

    private var weekCountLabel: some View {
        Text("Workouts this week: \(vm.workoutsThisWeek)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var monthYearTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: vm.currentMonth)
    }

    private var gridDays: [Date?] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: vm.currentMonth)
        ) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
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
