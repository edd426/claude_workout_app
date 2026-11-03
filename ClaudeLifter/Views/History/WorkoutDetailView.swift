import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    var onSave: ((@MainActor (Workout) async -> Void))? = nil
    /// Per-set edits go through the ViewModel so they re-queue the workout for
    /// sync (#117). Optional so existing previews keep compiling; when nil the
    /// rows are read-only.
    var onEditWeight: ((WorkoutSet, Double?) -> Void)? = nil
    var onEditReps: ((WorkoutSet, Int?) -> Void)? = nil
    /// Deletes the workout. The same action as History's swipe, so delete is
    /// never swipe-only (UI-P7). Nil hides it.
    var onDelete: (@MainActor () async -> Void)? = nil

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var isConfirmingDelete = false

    private var orderedExercises: [WorkoutExercise] {
        workout.exercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            if isEditing {
                workoutNameField
            } else {
                WorkoutDetailHeader(
                    workout: workout,
                    unit: deps?.settings.weightUnit ?? .kg
                )
            }
            ForEach(orderedExercises, id: \.id) { exercise in
                exerciseSection(exercise)
            }
        }
        .navigationTitle(isEditing ? editedName.isEmpty ? workout.name : editedName : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        // Back beside Cancel read as two ways out (§3.8); while editing,
        // Cancel is the way out.
        .navigationBarBackButtonHidden(isEditing)
        .toolbar { editToolbar }
        .confirmationDialog(
            "Delete \(workout.name)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Workout", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout and all its sets. It can't be undone.")
        }
        .onAppear {
            editedName = workout.name
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: WorkoutExercise) -> some View {
        let completed = exercise.sets.filter(\.isCompleted).sorted { $0.order < $1.order }
        let notLogged = exercise.sets.count - completed.count
        Section {
            if completed.isEmpty {
                // Planned sets that were never logged aren't data (#176).
                Label("Skipped", systemImage: "forward.end")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skippedExercise")
            } else {
                ForEach(completed, id: \.id) { set in
                    if isEditing, let onEditWeight, let onEditReps {
                        WorkoutSetEditRow(set: set, onEditWeight: onEditWeight, onEditReps: onEditReps)
                    } else {
                        WorkoutSetDetailRow(set: set)
                    }
                }
            }
        } header: {
            Text(exercise.exercise?.name ?? "Unknown")
        } footer: {
            if !completed.isEmpty, notLogged > 0 {
                Text(notLogged == 1 ? "1 planned set not logged" : "\(notLogged) planned sets not logged")
            }
        }
    }

    private var workoutNameField: some View {
        Section("Workout Name") {
            TextField("Name", text: $editedName)
        }
    }

    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if onSave != nil, onEditWeight != nil {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing {
                        commitEdits()
                    } else {
                        isEditing = true
                    }
                }
                .fontWeight(isEditing ? .semibold : .regular)
            }
        }
        if !isEditing, onDelete != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete Workout", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("workoutDetailMenu")
            }
        }
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    editedName = workout.name
                    isEditing = false
                }
            }
        }
    }

    @MainActor
    private func commitEdits() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            workout.name = trimmed
        }
        isEditing = false
        Task {
            await onSave?(workout)
        }
    }

    private func delete() {
        guard let onDelete else { return }
        Task {
            await onDelete()
            dismiss()
        }
    }
}

/// Date, duration, sets and volume, so a past workout reads at a glance
/// (§3.8). Counts are of completed sets only (#176).
private struct WorkoutDetailHeader: View {
    let workout: Workout
    let unit: WeightUnit

    var body: some View {
        let summary = WorkoutHistorySummary(workout)
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(workout.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { stats(summary) }
                    VStack(alignment: .leading, spacing: 8) { stats(summary) }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("workoutDetailHeader")
        }
    }

    @ViewBuilder
    private func stats(_ summary: WorkoutHistorySummary) -> some View {
        stat(summary.durationText, "Duration")
        stat("\(summary.completedSets)", summary.completedSets == 1 ? "Set" : "Sets")
        stat(summary.volumeText(in: unit), "Volume")
        if summary.skippedExercises > 0 {
            stat("\(summary.skippedExercises)", "Skipped")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutSetDetailRow: View {
    let set: WorkoutSet

    private var weightText: String? {
        // Locale-aware, matching the edit row — String(format:) always
        // renders a dot and disagreed with what the keypad accepted.
        self.set.weight.map {
            "\($0.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))) \(self.set.weightUnit.rawValue)"
        }
    }

    private var valueText: String {
        let reps = set.reps.map { "\($0) reps" } ?? "– reps"
        guard let weightText else { return "Bodyweight × \(reps)" }
        return "\(weightText) × \(reps)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.order + 1)")
                .foregroundStyle(.secondary)
            Text(valueText)
                .monospacedDigit()
            Spacer(minLength: 8)
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandTheme.completed)
                    .accessibilityLabel("completed")
            }
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }
}

private struct WorkoutSetEditRow: View {
    let set: WorkoutSet
    let onEditWeight: (WorkoutSet, Double?) -> Void
    let onEditReps: (WorkoutSet, Int?) -> Void

    @Environment(\.locale) private var locale

    // No local @State buffer, and no onAppear seeding. That pattern was
    // removed from SetRowView in #76 for clobbering newer model values, and
    // it was the last copy of it (#117). The binding reads the model, so an
    // emptied field is nil rather than a failed parse the write silently
    // skipped — and nil weight is how a bodyweight set is recorded.
    private var weightBinding: Binding<Double?> {
        Binding(get: { set.weight }, set: { onEditWeight(set, $0) })
    }

    private var repsBinding: Binding<Int?> {
        Binding(get: { set.reps }, set: { onEditReps(set, $0) })
    }

    private var weightFormat: FloatingPointFormatStyle<Double> {
        .number
            .locale(locale)
            .grouping(.never)
            .precision(.fractionLength(0...3))
    }

    private var repsFormat: IntegerFormatStyle<Int> {
        .number.locale(locale).grouping(.never)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.order + 1)")
                .foregroundStyle(.secondary)
            TextField("Weight", value: weightBinding, format: weightFormat)
                .keyboardType(.decimalPad)
                .frame(minWidth: 64)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Weight in \(set.weightUnit.rawValue)")
            Text(set.weightUnit.rawValue)
                .foregroundStyle(.secondary)
            TextField("Reps", value: repsBinding, format: repsFormat)
                .keyboardType(.numberPad)
                .frame(minWidth: 48)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Reps")
            Text("reps")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.body)
    }
}
