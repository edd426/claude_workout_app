import SwiftUI
import Combine
import UIKit

struct SetEntryFieldID: Hashable, Sendable {
    let exerciseID: UUID
    let setID: UUID
    let kind: Kind

    enum Kind: Hashable, Sendable {
        case weight
        case reps
    }
}

/// Pure ordering used by keyboard navigation. Stable model IDs distinguish
/// fields even though set orders repeat across exercises and change on removal.
func orderedSetEntryFields(in workout: Workout) -> [SetEntryFieldID] {
    workout.exercises
        .sorted(by: { $0.order < $1.order })
        .flatMap { workoutExercise in
            workoutExercise.sets
                .sorted(by: { $0.order < $1.order })
                .flatMap { set in
                    [
                        SetEntryFieldID(
                            exerciseID: workoutExercise.id,
                            setID: set.id,
                            kind: .weight
                        ),
                        SetEntryFieldID(
                            exerciseID: workoutExercise.id,
                            setID: set.id,
                            kind: .reps
                        ),
                    ]
                }
        }
}

func isSetEntryFieldAccessibilityIdentifier(_ identifier: String?) -> Bool {
    guard let identifier else { return false }
    let components = identifier.split(
        separator: "_",
        omittingEmptySubsequences: false
    )
    guard
        components.count == 3,
        components[0] == "weight" || components[0] == "reps"
    else {
        return false
    }
    return UUID(uuidString: String(components[1])) != nil
        && UUID(uuidString: String(components[2])) != nil
}

/// Identifies the exercise whose note is being edited (#136). A wrapper rather
/// than the model itself so `.sheet(item:)` keys on the stable UUID.
struct ExerciseNoteTarget: Identifiable {
    let workoutExercise: WorkoutExercise
    var id: UUID { workoutExercise.id }
    var exerciseName: String {
        workoutExercise.exercise?.name ?? "Exercise"
    }
}

struct ActiveWorkoutView: View {
    @State var vm: ActiveWorkoutViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var restSession: RestTimerSession?
    @State private var showExercisePicker = false
    @State private var showCancelDialog = false
    /// Non-nil while the report sheet is up; carries the captured context.
    @State private var reportContext: ReportContext?
    /// Non-nil while the per-exercise note editor is up (#136).
    @State private var noteTarget: ExerciseNoteTarget?
    @FocusState private var focusedField: SetEntryFieldID?
    @Environment(AppState.self) private var appState
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    private var orderedFields: [SetEntryFieldID] {
        guard let workout = vm.workout else { return [] }
        return orderedSetEntryFields(in: workout)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            workoutScreen
                .navigationTitle(vm.workout?.name ?? "Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent(scrollProxy: scrollProxy) }
                .task { await vm.startWorkout() }
                .sheet(isPresented: $showExercisePicker) { exercisePicker }
                .sheet(item: $reportContext) { context in
                    reportSheet(for: context)
                }
                .sheet(item: $noteTarget) { target in
                    ExerciseNoteEditorView(
                        exerciseName: target.exerciseName,
                        initialNotes: target.workoutExercise.exercise?.notes
                    ) { notes in
                        Task {
                            await vm.updateExerciseNotes(
                                target.workoutExercise,
                                notes: notes
                            )
                        }
                    }
                }
                .confirmationDialog(
                    "Exit workout?",
                    isPresented: $showCancelDialog
                ) {
                    exitDialogActions
                } message: {
                    exitDialogMessage
                }
                .onChange(of: orderedFields) { _, fields in
                    guard let focusedField else { return }
                    if !fields.contains(focusedField) {
                        self.focusedField = nil
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        restSession?.refreshFromClock()
                    } else if phase == .background {
                        performAfterFlushingFocusedField {
                            Task {
                                await vm.saveDraft()
                            }
                        }
                    }
                }
                .onDisappear {
                    restSession?.cancel()
                }
        }
        .selectAllTextOnBeginEditing()
    }

    @ViewBuilder
    private var workoutScreen: some View {
        if vm.workout != nil {
            workoutContent
        } else {
            ProgressView("Starting workout...")
        }
    }

    private var workoutContent: some View {
        VStack(spacing: 0) {
            errorBanner
            workoutScrollArea
        }
    }

    /// Surfaces ViewModel errors — most importantly a failed draft save,
    /// which previously happened silently and could lose logged sets on the
    /// next crash (#75). Same visual pattern as ChatView's error banner.
    @ViewBuilder
    private var errorBanner: some View {
        if let errorMsg = vm.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .accessibilityIdentifier("workoutErrorBanner")
        }
    }

    private var workoutScrollArea: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(
                    vm.workout?.exercises.sorted(
                        by: { $0.order < $1.order }
                    ) ?? [],
                    id: \.id
                ) { workoutExercise in
                    exerciseCard(for: workoutExercise)
                }
                addExerciseButton
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            restTimerInset
        }
    }

    private func exerciseCard(
        for workoutExercise: WorkoutExercise
    ) -> some View {
        ExerciseCardView(
            workoutExercise: workoutExercise,
            focusedField: $focusedField,
            previousValue: { vm.previous(for: $0) },
            onCompleteSet: { set in
                completeSetAfterFlushingField(
                    set,
                    restDuration: workoutExercise.restSeconds
                )
            },
            onEditWeight: { set, weight in
                vm.updateSetWeight(set, weight: weight)
            },
            onEditReps: { set, reps in
                vm.updateSetReps(set, reps: reps)
            },
            onAddSet: {
                vm.addSet(to: workoutExercise)
            },
            onRemoveSet: { set in
                focusedField = nil
                vm.removeSet(set, from: workoutExercise)
            },
            onReport: {
                focusedField = nil
                reportContext = .forExercise(workoutExercise, in: vm.workout)
            },
            onEditNotes: {
                focusedField = nil
                noteTarget = ExerciseNoteTarget(workoutExercise: workoutExercise)
            },
            plannedTarget: vm.plannedTarget(for: workoutExercise),
            previousDrifted: { set in
                vm.previousDriftedFromTarget(set, in: workoutExercise)
            }
        )
    }

    @ViewBuilder
    private func reportSheet(for context: ReportContext) -> some View {
        if let dependencies {
            ReportSheetView(
                vm: ReportSheetViewModel(
                    context: context,
                    repository: dependencies.exerciseReportRepository
                )
            )
        }
    }

    @ViewBuilder
    private var restTimerInset: some View {
        if let restSession,
           restSession.isRunning,
           focusedField == nil {
            RestTimerBarView(
                remainingSeconds: restSession.remainingSeconds,
                progress: restSession.progress,
                onSubtractTime: {
                    restSession.subtractTime(15)
                },
                onAddTime: {
                    restSession.addTime(15)
                },
                onSkip: {
                    restSession.skip()
                }
            )
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
    private func toolbarContent(
        scrollProxy: ScrollViewProxy
    ) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Exit") {
                if vm.hasCompletedSets {
                    showCancelDialog = true
                } else {
                    exitAndDiscardWorkout()
                }
            }
            .accessibilityIdentifier("cancelWorkout")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                focusedField = nil
                reportContext = .forWorkout(vm.workout)
            } label: {
                Label("Report a problem…", systemImage: "flag")
            }
            .accessibilityIdentifier("reportWorkout")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                finishWorkoutAfterFlushingField()
            } label: {
                if vm.isFinishing {
                    ProgressView()
                } else {
                    Text("Finish")
                }
            }
            .disabled(!vm.hasCompletedSets || vm.isFinishing)
            .foregroundStyle(BrandTheme.terracotta)
            .accessibilityIdentifier("finishWorkout")
        }
        ToolbarItemGroup(placement: .keyboard) {
            Button {
                focusAdjacentField(offset: -1, scrollProxy: scrollProxy)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!canFocusAdjacentField(offset: -1))
            .accessibilityLabel("Previous field")

            Button {
                focusAdjacentField(offset: 1, scrollProxy: scrollProxy)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!canFocusAdjacentField(offset: 1))
            .accessibilityLabel("Next field")

            if let restSession, restSession.isRunning {
                Text(formattedRestTime(restSession.remainingSeconds))
                    .font(.body.monospacedDigit())
                    .accessibilityLabel("Rest time remaining")
            }

            Spacer()
            Button("Done") {
                focusedField = nil
            }
        }
    }

    private var exercisePicker: some View {
        ExerciseLibraryView(selectionMode: true) { exercise in
            vm.addExercise(exercise)
        }
    }

    @ViewBuilder
    private var exitDialogActions: some View {
        Button("Discard — don't save", role: .destructive) {
            exitAndDiscardWorkout()
        }
        Button("Save progress as draft") {
            exitAndSaveDraft()
        }
        Button("Keep Going", role: .cancel) {}
    }

    private var exitDialogMessage: Text {
        Text(
            vm.hasCompletedSets
                ? "You've logged at least one set — saving keeps it in your history."
                : "Nothing logged yet, so discarding won't remove anything from your history."
        )
    }

    private func completeSetAfterFlushingField(
        _ set: WorkoutSet,
        restDuration: Int
    ) {
        performAfterFlushingFocusedField {
            if vm.completeSet(set) {
                startOrRestartRest(duration: restDuration)
            } else {
                restSession?.cancel()
            }
        }
    }

    private func finishWorkoutAfterFlushingField() {
        performAfterFlushingFocusedField {
            restSession?.cancel()
            Task {
                await vm.finishWorkout()
                // Leave the workout the moment the critical save has committed.
                // Deliberately not tied to the summary: the receipt is handed to
                // AppState and presented over Home, so dismissing it — Done,
                // swipe, or never appearing at all — cannot strand the user in a
                // workout that is already saved (#123).
                if case .finished(let summary) = vm.completionState {
                    appState.endWorkout(showing: summary)
                    onDismiss?()
                }
            }
        }
    }

    /// Resigning focus causes SwiftUI's formatted TextField to write through
    /// its binding asynchronously. The action must run on a later main-actor
    /// turn or completion / persistence can beat that final write.
    private func performAfterFlushingFocusedField(
        _ action: @escaping @MainActor () -> Void
    ) {
        guard focusedField != nil else {
            action()
            return
        }
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
            action()
        }
    }

    private func startOrRestartRest(duration: Int) {
        if let restSession {
            restSession.restart(duration: duration)
            return
        }
        let session = RestTimerSession(
            timerService: dependencies?.restTimerService
                ?? RestTimerService(),
            notificationScheduler: dependencies?.notificationScheduler
                ?? UserNotificationScheduler()
        )
        restSession = session
        session.start(duration: duration)
    }

    private func exitAndDiscardWorkout() {
        restSession?.cancel()
        Task {
            await vm.cancelWorkout()
            appState.endWorkout()
            onDismiss?()
        }
    }

    private func exitAndSaveDraft() {
        performAfterFlushingFocusedField {
            restSession?.cancel()
            Task {
                await vm.saveDraft()
                appState.endWorkout()
                onDismiss?()
            }
        }
    }

    private func canFocusAdjacentField(offset: Int) -> Bool {
        guard
            let focusedField,
            let currentIndex = orderedFields.firstIndex(of: focusedField)
        else {
            return false
        }
        return orderedFields.indices.contains(currentIndex + offset)
    }

    private func focusAdjacentField(
        offset: Int,
        scrollProxy: ScrollViewProxy
    ) {
        guard
            let focusedField,
            let currentIndex = orderedFields.firstIndex(of: focusedField),
            orderedFields.indices.contains(currentIndex + offset)
        else {
            return
        }
        let target = orderedFields[currentIndex + offset]
        scrollProxy.scrollTo(target.setID, anchor: .center)
        Task { @MainActor in
            await Task.yield()
            guard orderedFields.contains(target) else { return }
            self.focusedField = target
        }
    }
}

/// A single screen-level observer fixes append-on-edit for every formatted
/// numeric field without introducing row-owned copies of model values.
private struct SelectAllTextOnBeginEditing: ViewModifier {
    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(
                for: UITextField.textDidBeginEditingNotification
            )
        ) { notification in
            guard let textField = notification.object as? UITextField else {
                return
            }
            guard isSetEntryFieldAccessibilityIdentifier(
                textField.accessibilityIdentifier
            ) else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                textField.selectAll(nil)
            }
        }
    }
}

private extension View {
    func selectAllTextOnBeginEditing() -> some View {
        modifier(SelectAllTextOnBeginEditing())
    }
}
