import SwiftUI

/// What a card asks its screen to do: sheets, the rest timer and focus
/// flushing live on `ActiveWorkoutView`, so the card only reports intent.
struct ExerciseCardActions {
    /// Open or close this card; the screen flushes a focused field first.
    var onToggle: () -> Void
    var onCompleteSet: (WorkoutSet) -> Void
    var onRemoveSet: (WorkoutSet) -> Void
    /// Files a report against this exercise (#135).
    var onReport: () -> Void
    /// Opens the per-exercise note editor (#136).
    var onEditNotes: () -> Void
    /// Opens this workout's copy of the template's note (31A4983B, E26BBFAA).
    var onEditTemplateNote: () -> Void
    /// "Machine taken → Other…": the library, to swap in place (#169).
    var onSwapOther: () -> Void
    /// The machine photo, full screen (#170).
    var onShowPhoto: () -> Void
    /// "Remove from this workout"; the screen confirms when sets are logged.
    var onRemoveExercise: () -> Void
}

/// One exercise on the any-order workout screen.
///
/// Collapsed unless it is the card being worked: an untouched card is one
/// line (name, target, last time), a finished one says "✓ 3 × 8 @ 80 kg", a
/// skipped one is greyed. The whole header is the disclosure target (UI-P5).
struct ExerciseCardView: View {
    let vm: ActiveWorkoutViewModel
    let workoutExercise: WorkoutExercise
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let actions: ExerciseCardActions

    private var columns = SetRowColumns()

    init(
        vm: ActiveWorkoutViewModel,
        workoutExercise: WorkoutExercise,
        focusedField: FocusState<SetEntryFieldID?>.Binding,
        actions: ExerciseCardActions
    ) {
        self.vm = vm
        self.workoutExercise = workoutExercise
        self.focusedField = focusedField
        self.actions = actions
    }

    private var isExpanded: Bool { vm.isExpanded(workoutExercise) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExerciseCardHeader(
                vm: vm,
                workoutExercise: workoutExercise,
                actions: actions
            )
            if isExpanded {
                ExerciseCardDetail(
                    vm: vm,
                    workoutExercise: workoutExercise,
                    focusedField: focusedField,
                    columns: columns,
                    actions: actions
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BrandTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        // UI-H2: exercise swapped → selection. Fires for Undo too.
        .sensoryFeedback(.selection, trigger: workoutExercise.exercise?.id)
        .accessibilityElement(children: .contain)
    }
}

/// Photo, title (the disclosure), "Machine taken" and the card menu.
private struct ExerciseCardHeader: View {
    let vm: ActiveWorkoutViewModel
    let workoutExercise: WorkoutExercise
    let actions: ExerciseCardActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                titleButton
                HStack(spacing: 12) {
                    thumbnail
                    Spacer(minLength: 0)
                    controls
                }
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                thumbnail
                titleButton
                controls
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let exercise = workoutExercise.exercise {
            ExerciseThumbnail(
                exercise: exercise,
                generation: vm.photoGeneration,
                onShow: actions.onShowPhoto
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            if vm.canSwap(workoutExercise) {
                MachineTakenControl(
                    options: vm.alternatives(for: workoutExercise),
                    swappedFrom: vm.swappedFromName(for: workoutExercise),
                    onSwap: { exercise in
                        Task { await vm.swap(workoutExercise, to: exercise) }
                    },
                    onUndo: { Task { await vm.undoSwap(workoutExercise) } },
                    onOther: actions.onSwapOther
                )
            }
            ExerciseActionsMenu(
                vm: vm,
                workoutExercise: workoutExercise,
                actions: actions
            )
        }
    }

    private var progress: ExerciseProgress { vm.progress(for: workoutExercise) }
    private var isExpanded: Bool { vm.isExpanded(workoutExercise) }
    private var name: String { workoutExercise.exercise?.name ?? "Unknown Exercise" }

    private var titleButton: some View {
        Button(action: actions.onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(progress.status == .skipped ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    if let line = summaryLine {
                        Text(line)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(summaryColor)
                            .multilineTextAlignment(.leading)
                            .accessibilityIdentifier("exerciseSummary")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel([name, summaryLine].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityHint(isExpanded ? "Collapses this exercise" : "Shows this exercise's sets")
        .accessibilityIdentifier("exerciseHeader")
    }

    /// Expanded: the plan (#144), "3 × 8 · 90 s". Collapsed: the plan and
    /// last time, what was done, or that it was skipped.
    private var summaryLine: String? {
        let target = vm.plannedTarget(for: workoutExercise).map(SetEntryText.target)
        if isExpanded {
            return target
        }
        let summary = vm.collapsedSummary(for: workoutExercise)
        switch progress.status {
        case .untouched:
            return [target, summary].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        case .inProgress:
            let count = "\(progress.completedSets) of \(progress.totalSets)"
            return [count, summary].compactMap { $0 }.joined(separator: " · ")
        case .finished, .skipped:
            return summary
        }
    }

    private var summaryColor: Color {
        progress.status == .finished ? BrandTheme.accentText : .secondary
    }
}

/// The expanded part of a card: last done, notes, set rows, Add Set.
private struct ExerciseCardDetail: View {
    let vm: ActiveWorkoutViewModel
    let workoutExercise: WorkoutExercise
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let columns: SetRowColumns
    let actions: ExerciseCardActions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The template note starts collapsed to one line (report 31A4983B).
    @State private var isTemplateNoteExpanded = false
    /// The "last done" panel starts collapsed and costs no height until
    /// opened (#167); its content is loaded on first expand.
    @State private var isLastDoneExpanded = false
    @State private var recency: ExerciseRecency?
    @State private var recencyLoadFailed = false

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LastDoneToggle(
                muscles: workoutExercise.exercise?.primaryMuscles ?? [],
                isExpanded: $isLastDoneExpanded
            )
            if isLastDoneExpanded {
                LastDonePanel(recency: recency, loadFailed: recencyLoadFailed)
            }
            ExerciseNotesSection(
                exerciseNotes: ExerciseNotes.cleaned(workoutExercise.exercise?.notes),
                sessionNotes: ExerciseNotes.session(of: workoutExercise),
                isTemplateNoteExpanded: $isTemplateNoteExpanded,
                onEditNotes: actions.onEditNotes,
                onEditTemplateNote: actions.onEditTemplateNote
            )
            Divider()
            setRows
            addSetButton
        }
        .task(id: isLastDoneExpanded) { await loadRecencyIfNeeded() }
    }

    private func loadRecencyIfNeeded() async {
        guard isLastDoneExpanded, recency == nil else { return }
        recencyLoadFailed = false
        recency = await vm.recency(for: workoutExercise)
        recencyLoadFailed = recency == nil
    }

    @ViewBuilder
    private var setRows: some View {
        let layout: SetRowLayout = dynamicTypeSize.isAccessibilitySize ? .stacked : .compact
        VStack(spacing: layout == .stacked ? 12 : 2) {
            if layout == .compact {
                SetRowHeader(columns: columns)
            }
            ForEach(sortedSets, id: \.id) { set in
                SetRowView(
                    workoutExerciseID: workoutExercise.id,
                    set: set,
                    previousText: vm.previousText(for: set, in: workoutExercise),
                    drifted: vm.driftTarget(for: set, in: workoutExercise) != nil,
                    layout: layout,
                    columns: columns,
                    focusedField: focusedField,
                    onComplete: actions.onCompleteSet,
                    onEditWeight: { vm.updateSetWeight($0, weight: $1) },
                    onEditReps: { vm.updateSetReps($0, reps: $1) }
                )
                .id(set.id)
            }
        }
    }

    /// A full-width row button, at least 44 pt tall (UI-T1).
    private var addSetButton: some View {
        Button {
            vm.addSet(to: workoutExercise)
        } label: {
            Label("Add Set", systemImage: "plus")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .accessibilityIdentifier("addSet")
    }
}

/// The primary muscles line, which doubles as the "last done" disclosure
/// (#167).
private struct LastDoneToggle: View {
    let muscles: [String]
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = muscles.joined(separator: ", ")
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                Text(muscles.isEmpty ? "Last done" : "Last done · \(text)")
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muscles.isEmpty ? "Last done" : "Last done, \(text)")
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
        .accessibilityIdentifier("lastDoneToggle")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
