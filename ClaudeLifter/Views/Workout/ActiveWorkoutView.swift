import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @State var vm: ActiveWorkoutViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var showRestTimer = false
    @State private var restDuration = 90
    @State private var showSummary = false
    @State private var showExercisePicker = false
    @State private var showCancelDialog = false
    @Environment(AppState.self) private var appState

    var body: some View {
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
        .task {
            if vm.workout == nil {
                await vm.startWorkout()
            }
        }
        .sheet(isPresented: $showSummary) {
            if let workout = vm.workout {
                WorkoutSummaryView(workout: workout, personalRecords: vm.detectedPRs) {
                    showSummary = false
                    appState.endWorkout()
                    onDismiss?()
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
        .confirmationDialog("End Workout?", isPresented: $showCancelDialog) {
            Button("Save as Draft") {
                Task {
                    await vm.saveDraft()
                    appState.endWorkout()
                    onDismiss?()
                }
            }
            Button("Discard Workout", role: .destructive) {
                Task {
                    await vm.cancelWorkout()
                    appState.endWorkout()
                    onDismiss?()
                }
            }
            Button("Keep Going", role: .cancel) {}
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
                            },
                            onRemoveSet: { set in
                                vm.removeSet(set, from: we)
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
        .accessibilityIdentifier("addExerciseToWorkout")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                showCancelDialog = true
            }
            .accessibilityIdentifier("cancelWorkout")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Finish") {
                Task { await vm.finishWorkout() }
            }
            .disabled(!vm.hasCompletedSets)
            .foregroundStyle(BrandTheme.terracotta)
            .accessibilityIdentifier("finishWorkout")
        }
    }
}
