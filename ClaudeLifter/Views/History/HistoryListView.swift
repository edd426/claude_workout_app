import SwiftUI

struct HistoryListView: View {
    @Environment(\.dependencies) private var deps
    @State private var vm: HistoryViewModel?
    @State private var calendarVM: CalendarViewModel?
    @State private var showCalendar = true
    @State private var workoutToDelete: Workout? = nil
    /// Bumped on every confirmed delete, for the `.warning` haptic (UI-H2).
    @State private var deletions = 0

    var body: some View {
        NavigationStack {
            Group {
                if let vm, let calendarVM {
                    historyContent(vm: vm, calendarVM: calendarVM)
                } else {
                    ProgressView("Loading history…")
                }
            }
            .navigationTitle("History")
            .toolbar { viewToggleToolbar }
        }
        // A confirmation dialog, destructive first and Cancel last (UI-P6).
        .confirmationDialog(
            "Delete \(workoutToDelete?.name ?? "workout")?",
            isPresented: Binding(
                get: { workoutToDelete != nil },
                set: { if !$0 { workoutToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: workoutToDelete
        ) { workout in
            Button("Delete Workout", role: .destructive) {
                workoutToDelete = nil
                Task { await delete(workout) }
            }
            Button("Cancel", role: .cancel) { workoutToDelete = nil }
        } message: { _ in
            Text("This removes the workout and all its sets. It can't be undone.")
        }
        .sensoryFeedback(.warning, trigger: deletions)
        .task {
            // Construct once, but reload on every appearance (#132). Loading
            // inside the `vm == nil` guard meant the fetch ran once per launch,
            // so anyone who opened History early in a session saw a list frozen
            // at that moment — including after finishing a workout, which is
            // the case that actually matters.
            if vm == nil, let deps {
                vm = HistoryViewModel(workoutRepository: deps.workoutRepository)
                calendarVM = CalendarViewModel(workoutRepository: deps.workoutRepository)
            }
            await vm?.loadWorkouts()
            // The heatmap has its own `.task`, but it only covers the case
            // where that subview is on screen; reload here so the calendar
            // cannot go stale independently of the list.
            await calendarVM?.loadMonth()
        }
    }

    private func delete(_ workout: Workout) async {
        await vm?.deleteWorkout(workout)
        deletions += 1
        await calendarVM?.loadMonth()
        if let date = calendarVM?.selectedDate {
            await calendarVM?.selectDate(date)
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
                    Label("Progress charts", systemImage: "chart.line.uptrend.xyaxis")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        // One labelled toggle. The segmented picker's icon segments read as
        // "calendar" and "list.bullet" to VoiceOver whatever label they got
        // (UI-A1).
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCalendar.toggle()
            } label: {
                Label(
                    showCalendar ? "Show list" : "Show calendar",
                    systemImage: showCalendar ? "list.bullet" : "calendar"
                )
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("historyViewToggle")
        }
    }

    private func historyContent(vm: HistoryViewModel, calendarVM: CalendarViewModel) -> some View {
        VStack(spacing: 0) {
            if let message = vm.errorMessage ?? calendarVM.errorMessage {
                HistoryErrorBanner(message: message) {
                    Task {
                        await vm.loadWorkouts()
                        await calendarVM.loadMonth()
                    }
                }
            }
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

    /// The workout's detail screen, with every edit and the delete routed
    /// through the ViewModel (#117, UI-P7).
    private func detail(for workout: Workout, vm: HistoryViewModel) -> some View {
        WorkoutDetailView(
            workout: workout,
            onSave: { updated in
                await vm.updateWorkout(updated)
            },
            onEditWeight: { set, weight in
                Task { await vm.updateSet(set, weight: weight, in: workout) }
            },
            onEditReps: { set, reps in
                Task { await vm.updateSet(set, reps: reps, in: workout) }
            },
            onDelete: {
                await delete(workout)
            }
        )
    }

    /// A row outside a `List`. `.plain` keeps the label from taking the
    /// accent tint, which made the rows read as links (§3.8).
    private func plainRow(_ workout: Workout, vm: HistoryViewModel) -> some View {
        NavigationLink {
            detail(for: workout, vm: vm)
        } label: {
            HStack(spacing: 8) {
                WorkoutHistoryRowView(workout: workout)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .contextMenu {
            Button("Delete Workout", systemImage: "trash", role: .destructive) {
                workoutToDelete = workout
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
                            plainRow(workout, vm: historyVM)
                            Divider().padding(.leading)
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
                emptyState(isLoading: vm.isLoading)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(vm.completedWorkouts, id: \.id) { workout in
                        plainRow(workout, vm: vm)
                        Divider().padding(.leading)
                    }
                }
            }
        }
    }

    private func listView(vm: HistoryViewModel) -> some View {
        Group {
            if vm.completedWorkouts.isEmpty {
                emptyState(isLoading: vm.isLoading)
            } else {
                List(vm.completedWorkouts, id: \.id) { workout in
                    NavigationLink {
                        detail(for: workout, vm: vm)
                    } label: {
                        WorkoutHistoryRowView(workout: workout)
                    }
                    // Also in the detail screen's menu, so never swipe-only
                    // (UI-P7); never on a full swipe (UI-P6).
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            workoutToDelete = workout
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(BrandTheme.destructive)
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.loadWorkouts() }
            }
        }
    }

    @ViewBuilder
    private func emptyState(isLoading: Bool) -> some View {
        if isLoading {
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            ContentUnavailableView(
                "No workouts yet",
                systemImage: "calendar.badge.clock",
                description: Text("Finish a workout from Today and it shows up here.")
            )
        }
    }
}

/// Inline error with Retry (UI-E1).
private struct HistoryErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BrandTheme.warning)
                .accessibilityHidden(true)
            Text("Couldn't load history: \(message)")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(BrandTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
