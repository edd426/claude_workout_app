import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var vm: HistoryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    historyContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("History")
        }
        .task {
            if vm == nil {
                vm = HistoryViewModel(
                    workoutRepository: SwiftDataWorkoutRepository(context: modelContext)
                )
                await vm?.loadWorkouts()
            }
        }
    }

    private func historyContent(vm: HistoryViewModel) -> some View {
        Group {
            if vm.completedWorkouts.isEmpty {
                emptyState
            } else {
                workoutList(vm: vm)
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

    private func workoutList(vm: HistoryViewModel) -> some View {
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
