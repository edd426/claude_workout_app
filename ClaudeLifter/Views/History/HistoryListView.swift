import SwiftUI

struct HistoryListView: View {
    @Environment(\.dependencies) private var deps
    @State private var vm: HistoryViewModel?
    @State private var calendarVM: CalendarViewModel?
    @State private var showCalendar = true
    @State private var workoutToDelete: Workout? = nil

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
        .alert("Delete Workout?", isPresented: Binding(
            get: { workoutToDelete != nil },
            set: { if !$0 { workoutToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let workout = workoutToDelete {
                    workoutToDelete = nil
                    Task { await vm?.deleteWorkout(workout) }
                }
            }
            Button("Cancel", role: .cancel) { workoutToDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
        .task {
            if vm == nil, let deps {
                vm = HistoryViewModel(workoutRepository: deps.workoutRepository)
                calendarVM = CalendarViewModel(workoutRepository: deps.workoutRepository)
                await vm?.loadWorkouts()
            }
        }
    }

    @ToolbarContentBuilder
    private var viewToggleToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if vm != nil, let deps {
                NavigationLink {
                    ChartsView(viewModel: ProgressChartsViewModel(
                        workoutRepository: deps.workoutRepository,
                        exerciseRepository: deps.exerciseRepository
                    ))
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(BrandTheme.terracotta)
                }
            }
        }
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
                                WorkoutDetailView(workout: workout, onSave: { updated in
                                    await historyVM.updateWorkout(updated)
                                })
                            } label: {
                                WorkoutHistoryRowView(workout: workout)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    workoutToDelete = workout
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
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
                            WorkoutDetailView(workout: workout, onSave: { updated in
                                await vm.updateWorkout(updated)
                            })
                        } label: {
                            WorkoutHistoryRowView(workout: workout)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                workoutToDelete = workout
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
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
                        WorkoutDetailView(workout: workout, onSave: { updated in
                            await vm.updateWorkout(updated)
                        })
                    } label: {
                        WorkoutHistoryRowView(workout: workout)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            workoutToDelete = workout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
