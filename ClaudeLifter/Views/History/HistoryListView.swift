import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm: HistoryViewModel?
    @State private var calendarVM: CalendarViewModel?
    @State private var showCalendar = true

    var body: some View {
        NavigationStack {
            Group {
                if let vm, let calendarVM {
                    historyContent(vm: vm, calendarVM: calendarVM)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("History")
            .toolbar { viewToggleToolbar }
        }
        .task {
            if vm == nil {
                let repo = SwiftDataWorkoutRepository(context: modelContext)
                vm = HistoryViewModel(workoutRepository: repo)
                calendarVM = CalendarViewModel(workoutRepository: repo)
                await vm?.loadWorkouts()
            }
        }
    }

    private var viewToggleToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Picker("View", selection: $showCalendar) {
                Image(systemName: "calendar").tag(true)
                Image(systemName: "list.bullet").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
        }
    }

    private func historyContent(vm: HistoryViewModel, calendarVM: CalendarViewModel) -> some View {
        Group {
            if showCalendar {
                calendarView(vm: vm, calendarVM: calendarVM)
            } else {
                listView(vm: vm)
            }
        }
    }

    private func calendarView(vm: HistoryViewModel, calendarVM: CalendarViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CalendarHeatmapView(vm: calendarVM)
                    .padding(.vertical)
                Divider()
                selectedDaySection(calendarVM: calendarVM, historyVM: vm)
            }
        }
    }

    private func selectedDaySection(calendarVM: CalendarViewModel, historyVM: HistoryViewModel) -> some View {
        Group {
            if let selectedDate = calendarVM.selectedDate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedDate, style: .date)
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    if calendarVM.selectedDayWorkouts.isEmpty {
                        Text("No completed workouts on this day.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    } else {
                        ForEach(calendarVM.selectedDayWorkouts, id: \.id) { workout in
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                WorkoutHistoryRowView(workout: workout)
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            } else {
                recentWorkoutsList(vm: historyVM)
            }
        }
    }

    private func recentWorkoutsList(vm: HistoryViewModel) -> some View {
        Group {
            if vm.completedWorkouts.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vm.completedWorkouts, id: \.id) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutHistoryRowView(workout: workout)
                        }
                        .padding(.horizontal)
                        Divider().padding(.leading)
                    }
                }
            }
        }
    }

    private func listView(vm: HistoryViewModel) -> some View {
        Group {
            if vm.completedWorkouts.isEmpty {
                emptyState
            } else {
                List(vm.completedWorkouts, id: \.id) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        WorkoutHistoryRowView(workout: workout)
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.loadWorkouts() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No workouts yet")
                .font(.headline)
            Text("Complete a workout to see your history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
