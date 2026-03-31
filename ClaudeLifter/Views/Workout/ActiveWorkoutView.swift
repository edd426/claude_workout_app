import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @State var vm: ActiveWorkoutViewModel
    @State private var showRestTimer = false
    @State private var restDuration = 90
    @State private var showSummary = false
    @State private var showExercisePicker = false
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if vm.workout != nil {
                    workoutContent
                } else {
                    ProgressView("Starting workout...")
                }
            }
            .navigationTitle(vm.workout?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await vm.startWorkout() }
        .sheet(isPresented: $showSummary) {
            if let workout = vm.workout {
                WorkoutSummaryView(workout: workout, personalRecords: vm.detectedPRs) {
                    showSummary = false
                    appState.endWorkout()
                }
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            ExerciseLibraryView(selectionMode: true) { exercise in
                vm.addExercise(exercise)
            }
        }
        .onChange(of: vm.isFinished) { _, finished in
            if finished { showSummary = true }
        }
    }

    private var workoutContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.workout?.exercises.sorted(by: { $0.order < $1.order }) ?? [], id: \.id) { we in
                        ExerciseCardView(
                            workoutExercise: we,
                            onCompleteSet: { set in
                                vm.completeSet(set)
                                restDuration = we.restSeconds
                                showRestTimer = true
                            },
                            onAddSet: {
                                let nextOrder = (we.sets.map(\.order).max() ?? -1) + 1
                                we.sets.append(WorkoutSet(order: nextOrder))
                            }
                        )
                    }
                    addExerciseButton
                }
                .padding()
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)

            if showRestTimer {
                RestTimerOverlayView(durationSeconds: restDuration) {
                    showRestTimer = false
                }
                .padding()
            }
        }
    }

    private var addExerciseButton: some View {
        Button {
            showExercisePicker = true
        } label: {
            Label("Add Exercise", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Finish") {
                Task { await vm.finishWorkout() }
            }
            .foregroundStyle(BrandTheme.terracotta)
        }
    }
}
