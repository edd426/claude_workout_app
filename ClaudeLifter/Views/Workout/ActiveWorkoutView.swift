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
                        SetEntryFieldID(exerciseID: workoutExercise.id, setID: set.id, kind: .weight),
                        SetEntryFieldID(exerciseID: workoutExercise.id, setID: set.id, kind: .reps),
                    ]
                }
        }
}

func isSetEntryFieldAccessibilityIdentifier(_ identifier: String?) -> Bool {
    guard let identifier else { return false }
    let components = identifier.split(separator: "_", omittingEmptySubsequences: false)
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
    var kind: ExerciseNoteKind = .exercise
    var id: UUID { workoutExercise.id }
    var exerciseName: String {
        workoutExercise.exercise?.name ?? "Exercise"
    }
}

/// Why the library picker is up: to add an exercise, or to swap one in place
/// ("Machine taken → Other…", #169).
enum ExercisePickerPurpose: Identifiable {
    case add
    case swap(WorkoutExercise)

    var id: String {
        switch self {
        case .add: return "add"
        case .swap(let workoutExercise): return "swap-\(workoutExercise.id)"
        }
    }
}

/// The active workout as an any-order screen (1.9.0, evaluation item 1).
///
/// One strip of chips shows what's done and what's left; one card is open at
/// a time and the user's tap decides which. Cards are in a plain `VStack`, not
/// a `LazyVStack`: with variable-height cards the lazy stack's size estimates
/// kept changing at the end of the scroll range and the main thread never
/// went idle (#172, UI-E5). A workout has a handful of cards, so laziness
/// bought nothing.
struct ActiveWorkoutView: View {
    @State var vm: ActiveWorkoutViewModel
    var onDismiss: (() -> Void)? = nil

    @State private var restSession: RestTimerSession?
    @State private var picker: ExercisePickerPurpose?
    @State private var showCancelDialog = false
    /// Non-nil while the report sheet is up; carries the captured context.
    @State private var reportContext: ReportContext?
    /// Non-nil while the per-exercise note editor is up (#136).
    @State private var noteTarget: ExerciseNoteTarget?
    /// Non-nil while a machine photo is full screen (#170).
    @State private var photoTarget: ExercisePhotoTarget?
    /// An exercise with logged sets waiting on "Remove from this workout".
    @State private var removalTarget: WorkoutExercise?
    @FocusState private var focusedField: SetEntryFieldID?
    @Environment(AppState.self) private var appState
    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keyboard navigation covers the open card only: collapsed cards have
    /// no fields on screen.
    private var orderedFields: [SetEntryFieldID] {
        guard let workout = vm.workout, let open = vm.expandedExerciseId else { return [] }
        return orderedSetEntryFields(in: workout).filter { $0.exerciseID == open }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            presentations(
                workoutScreen(scrollProxy: scrollProxy)
                    .navigationTitle(vm.workout?.name ?? "Workout")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent(scrollProxy: scrollProxy) }
                    .task { await start() }
            )
            .onChange(of: vm.expandedExerciseId) { _, open in
                if let focusedField, focusedField.exerciseID != open {
                    self.focusedField = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
            .onDisappear { restSession?.cancel() }
            // UI-H2: rest finished → success, from the view (UI-H1).
            .sensoryFeedback(.success, trigger: restSession?.restFinishedCount ?? 0)
        }
        .caretAtEndOnBeginEditing()
    }

    /// Sheets, the photo cover and the two confirmation dialogs.
    private func presentations<Content: View>(_ content: Content) -> some View {
        content
            .sheet(item: $picker) { exercisePicker(for: $0) }
            .sheet(item: $reportContext) { reportSheet(for: $0) }
            .sheet(item: $noteTarget) { noteEditor(for: $0) }
            .fullScreenCover(item: $photoTarget) { ExercisePhotoViewer(target: $0) }
            .confirmationDialog("Exit workout?", isPresented: $showCancelDialog) {
                exitDialogActions
            } message: {
                exitDialogMessage
            }
            .confirmationDialog(removalTitle, isPresented: removalBinding, titleVisibility: .visible) {
                removalActions
            } message: {
                Text("Its logged sets are deleted from this workout. The template is not changed.")
            }
    }

    private func start() async {
        if let dependencies {
            vm.useAlternatives(from: dependencies.exerciseAlternativeRepository)
        }
        await vm.startWorkout()
        if let dependencies {
            await vm.fetchMissingPhotos(using: dependencies.exercisePhotoFetcher)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            restSession?.refreshFromClock()
            autoFinishIfIdle()
        } else if phase == .background {
            performAfterFlushingFocusedField {
                Task { await vm.saveDraft() }
            }
        }
    }

    @ViewBuilder
    private func workoutScreen(scrollProxy: ScrollViewProxy) -> some View {
        if vm.workout != nil {
            VStack(spacing: 0) {
                errorBanner
                if !vm.orderedExercises.isEmpty {
                    ExerciseStripView(vm: vm) { open($0, scrollProxy: scrollProxy) }
                }
                workoutScrollArea(scrollProxy: scrollProxy)
            }
        } else {
            ProgressView("Starting workout…")
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
                    .foregroundStyle(BrandTheme.warning)
                    .accessibilityHidden(true)
                Text(errorMsg)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .accessibilityIdentifier("workoutErrorBanner")
        }
    }

    private func workoutScrollArea(scrollProxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(vm.orderedExercises, id: \.id) { workoutExercise in
                    exerciseCard(for: workoutExercise, scrollProxy: scrollProxy)
                        .id(workoutExercise.id)
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
        for workoutExercise: WorkoutExercise,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        ExerciseCardView(
            vm: vm,
            workoutExercise: workoutExercise,
            focusedField: $focusedField,
            actions: cardActions(for: workoutExercise, scrollProxy: scrollProxy)
        )
    }

    private func cardActions(
        for workoutExercise: WorkoutExercise,
        scrollProxy: ScrollViewProxy
    ) -> ExerciseCardActions {
        ExerciseCardActions(
            onToggle: { toggle(workoutExercise) },
            onCompleteSet: { set in
                completeSetAfterFlushingField(set, restDuration: workoutExercise.restSeconds)
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
            onEditTemplateNote: {
                focusedField = nil
                noteTarget = ExerciseNoteTarget(workoutExercise: workoutExercise, kind: .template)
            },
            onSwapOther: {
                focusedField = nil
                picker = .swap(workoutExercise)
            },
            onShowPhoto: { showPhoto(of: workoutExercise) },
            onRemoveExercise: { requestRemoval(of: workoutExercise) }
        )
    }

    /// A strip chip: open that card and bring it to the top.
    private func open(_ workoutExercise: WorkoutExercise, scrollProxy: ScrollViewProxy) {
        performAfterFlushingFocusedField {
            vm.expand(workoutExercise)
            Task { @MainActor in
                await Task.yield()
                withAnimation(reduceMotion ? nil : .snappy) {
                    scrollProxy.scrollTo(workoutExercise.id, anchor: .top)
                }
            }
        }
    }

    /// A card header: open or close it. A focused field in a closing card is
    /// flushed first, so its last keystrokes are not lost with the field.
    private func toggle(_ workoutExercise: WorkoutExercise) {
        performAfterFlushingFocusedField {
            vm.toggleExpansion(workoutExercise)
        }
    }

    private func showPhoto(of workoutExercise: WorkoutExercise) {
        guard
            let exercise = workoutExercise.exercise,
            let source = ExercisePhotoSource(exercise: exercise)
        else { return }
        focusedField = nil
        photoTarget = ExercisePhotoTarget(
            id: workoutExercise.id,
            name: exercise.name,
            source: source,
            note: ExerciseNotes.cleaned(exercise.notes)
        )
    }

    /// Removing logged sets is data loss, so it is confirmed (UI-P6). An
    /// exercise with nothing logged goes at once: there is nothing to lose.
    private func requestRemoval(of workoutExercise: WorkoutExercise) {
        focusedField = nil
        if workoutExercise.sets.contains(where: \.isCompleted) {
            removalTarget = workoutExercise
        } else {
            vm.removeExercise(workoutExercise)
        }
    }

    private var removalTitle: String {
        "Remove \(removalTarget?.exercise?.name ?? "this exercise") from this workout?"
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { removalTarget != nil },
            set: { if !$0 { removalTarget = nil } }
        )
    }

    @ViewBuilder
    private var removalActions: some View {
        Button("Remove", role: .destructive) {
            if let removalTarget {
                vm.removeExercise(removalTarget)
            }
            removalTarget = nil
        }
        Button("Cancel", role: .cancel) { removalTarget = nil }
    }

    @ViewBuilder
    private func reportSheet(for context: ReportContext) -> some View {
        if let dependencies {
            ReportSheetView(
                vm: ReportSheetViewModel(
                    context: context,
                    repository: dependencies.exerciseReportRepository,
                    photoStore: dependencies.reportPhotoStore
                )
            )
        }
    }

    @ViewBuilder
    private var restTimerInset: some View {
        if let restSession, focusedField == nil {
            RestTimerInset(session: restSession)
        }
    }

    private var addExerciseButton: some View {
        Button {
            focusedField = nil
            picker = .add
        } label: {
            Label("Add Exercise", systemImage: "plus.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .padding(.top, 8)
        .accessibilityIdentifier("addExerciseToWorkout")
    }

    @ToolbarContentBuilder
    private func toolbarContent(scrollProxy: ScrollViewProxy) -> some ToolbarContent {
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
            finishButton
        }
        ToolbarItemGroup(placement: .keyboard) {
            keyboardBar(scrollProxy: scrollProxy)
        }
    }

    /// The screen's one prominent action (UI-P9).
    private var finishButton: some View {
        Button {
            finishWorkoutAfterFlushingField()
        } label: {
            if vm.isFinishing {
                ProgressView()
            } else {
                Text("Finish").bold()
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTheme.accent)
        .disabled(!vm.hasCompletedSets || vm.isFinishing)
        .accessibilityIdentifier("finishWorkout")
    }

    /// Up / down between fields; −2.5 / +2.5 while a weight is focused; and
    /// "✓ Log set", so a +2.5 kg set is three taps and no keys.
    @ViewBuilder
    private func keyboardBar(scrollProxy: ScrollViewProxy) -> some View {
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

        if focusedField?.kind == .weight {
            Button("−2.5") { adjustFocusedWeight(by: -2.5) }
                .monospacedDigit()
                .accessibilityLabel("Minus 2.5")
                .accessibilityIdentifier("weightMinus")
            Button("+2.5") { adjustFocusedWeight(by: 2.5) }
                .monospacedDigit()
                .accessibilityLabel("Plus 2.5")
                .accessibilityIdentifier("weightPlus")
        }

        Spacer()

        if let restSession, focusedField?.kind != .weight {
            RestTimeLabel(session: restSession)
        }

        Button {
            logFocusedSet()
        } label: {
            Label("Log set", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
        }
        .bold()
        .disabled(focusedEntry?.set.isCompleted ?? true)
        .accessibilityIdentifier("logFocusedSet")

        Button("Done") {
            focusedField = nil
        }
    }

    private var focusedEntry: (workoutExercise: WorkoutExercise, set: WorkoutSet)? {
        guard let focusedField else { return nil }
        return vm.entry(exerciseID: focusedField.exerciseID, setID: focusedField.setID)
    }

    /// Commits whatever is typed, steps the weight, and puts the caret back.
    private func adjustFocusedWeight(by delta: Double) {
        guard let field = focusedField, field.kind == .weight, let entry = focusedEntry else { return }
        performAfterFlushingFocusedField {
            vm.adjustWeight(entry.set, by: delta)
            Task { @MainActor in
                await Task.yield()
                focusedField = field
            }
        }
    }

    private func logFocusedSet() {
        guard let entry = focusedEntry, !entry.set.isCompleted else { return }
        completeSetAfterFlushingField(entry.set, restDuration: entry.workoutExercise.restSeconds)
    }

    @ViewBuilder
    private func exercisePicker(for purpose: ExercisePickerPurpose) -> some View {
        switch purpose {
        case .add:
            ExerciseLibraryView(selectionMode: true) { exercise in
                vm.addExercise(exercise)
            }
        case .swap(let workoutExercise):
            ExerciseLibraryView(
                selectionMode: true,
                onSelect: { exercise in
                    Task { await vm.swap(workoutExercise, to: exercise) }
                },
                initialMuscleFilter: vm.primaryMuscle(for: workoutExercise)
            )
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

    private func completeSetAfterFlushingField(_ set: WorkoutSet, restDuration: Int) {
        performAfterFlushingFocusedField {
            if vm.completeSet(set) {
                startOrRestartRest(duration: restDuration)
            } else {
                restSession?.cancel()
            }
        }
    }

    private func noteEditor(for target: ExerciseNoteTarget) -> some View {
        let workoutExercise = target.workoutExercise
        return ExerciseNoteEditorView(
            exerciseName: target.exerciseName,
            initialNotes: target.kind == .exercise
                ? workoutExercise.exercise?.notes
                : workoutExercise.notes,
            kind: target.kind
        ) { notes in
            switch target.kind {
            case .exercise:
                Task { await vm.updateExerciseNotes(workoutExercise, notes: notes) }
            case .template:
                vm.updateTemplateNote(workoutExercise, notes: notes)
            }
        }
    }

    /// Coming back to a workout that has sat idle for hours finishes it and
    /// shows the receipt over Home, which says it was automatic (report
    /// 07B1AD96). Past the policy check this is the Finish button's path —
    /// flush the focused field, then finish — so an ordinary return to the
    /// app never touches the keyboard.
    private func autoFinishIfIdle() {
        guard
            let workout = vm.workout,
            WorkoutAutoFinishPolicy.window(for: workout, now: .now) != nil
        else { return }
        performAfterFlushingFocusedField {
            restSession?.cancel()
            Task {
                guard await vm.autoFinishIfIdle() else { return }
                if case .finished(let summary) = vm.completionState {
                    appState.endWorkout(showing: summary)
                    onDismiss?()
                }
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
    private func performAfterFlushingFocusedField(_ action: @escaping @MainActor () -> Void) {
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
            // A cancelled sleep only shortens the wait; the action still runs.
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
            timerService: dependencies?.restTimerService ?? RestTimerService(),
            notificationScheduler: dependencies?.notificationScheduler ?? UserNotificationScheduler()
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

    private func focusAdjacentField(offset: Int, scrollProxy: ScrollViewProxy) {
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

/// The rest bar, reading the countdown itself: the per-second tick then
/// re-renders this view only, not the whole workout screen (UI-E5).
private struct RestTimerInset: View {
    let session: RestTimerSession

    var body: some View {
        if session.isRunning {
            RestTimerBarView(
                remainingSeconds: session.remainingSeconds,
                progress: session.progress,
                onSubtractTime: { session.subtractTime(15) },
                onAddTime: { session.addTime(15) },
                onSkip: { session.skip() }
            )
        }
    }
}

/// The rest time in the keyboard bar, which takes over from the hidden rest
/// bar while a field is focused.
private struct RestTimeLabel: View {
    let session: RestTimerSession

    var body: some View {
        if session.isRunning {
            Text(formattedRestTime(session.remainingSeconds))
                .font(.body.monospacedDigit())
                .accessibilityLabel("Rest time remaining")
        }
    }
}

/// A single screen-level observer puts the caret at the end of every set
/// field that begins editing — including fields focused by the keyboard bar's
/// previous/next buttons, which no tap is involved in.
///
/// This used to select all, so typing replaced the value (40 → 45, not 4045).
/// Report 8FF8C6D5 asked for the caret at the end instead, so one backspace
/// corrects a digit; typing now appends, which is the trade that was chosen.
/// The first tap's own caret placement is handled in `SetRowView`
/// (`FocusWithCaretAtEnd`), because this hop loses the race with it on device.
private struct CaretAtEndOnBeginEditing: ViewModifier {
    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
        ) { notification in
            guard let textField = notification.object as? UITextField else { return }
            guard isSetEntryFieldAccessibilityIdentifier(textField.accessibilityIdentifier) else {
                return
            }
            Task { @MainActor in
                await Task.yield()
                let end = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: end, to: end)
            }
        }
    }
}

private extension View {
    func caretAtEndOnBeginEditing() -> some View {
        modifier(CaretAtEndOnBeginEditing())
    }
}
