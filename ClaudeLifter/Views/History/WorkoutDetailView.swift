import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    var onSave: ((@MainActor (Workout) async -> Void))? = nil
    /// Per-set edits go through the ViewModel so they re-queue the workout for
    /// sync (#117). Optional so existing previews keep compiling; when nil the
    /// rows are read-only.
    var onEditWeight: ((WorkoutSet, Double?) -> Void)? = nil
    var onEditReps: ((WorkoutSet, Int?) -> Void)? = nil

    @State private var isEditing = false
    @State private var editedName: String = ""

    var body: some View {
        List {
            if isEditing {
                workoutNameField
            }
            ForEach(workout.exercises.sorted(by: { $0.order < $1.order }), id: \.id) { we in
                Section(we.exercise?.name ?? "Unknown") {
                    ForEach(we.sets.sorted(by: { $0.order < $1.order }), id: \.id) { set in
                        if isEditing, let onEditWeight, let onEditReps {
                            WorkoutSetEditRow(
                                set: set,
                                onEditWeight: onEditWeight,
                                onEditReps: onEditReps
                            )
                        } else {
                            WorkoutSetDetailRow(set: set)
                        }
                    }
                }
            }
        }
        .navigationTitle(isEditing ? editedName.isEmpty ? workout.name : editedName : workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            editToolbar
        }
        .onAppear {
            editedName = workout.name
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
}

private struct WorkoutSetDetailRow: View {
    let set: WorkoutSet

    var body: some View {
        HStack {
            Text("Set \(set.order + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            if let weight = set.weight {
                // Locale-aware, matching the edit row — String(format:) always
                // renders a dot and disagreed with what the keypad accepted.
                Text("\(weight.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))) \(set.weightUnit.rawValue)")
                    .frame(width: 80)
            }
            if let reps = set.reps {
                Text("× \(reps) reps")
            }
            Spacer()
            if set.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.body)
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
                .frame(width: 48, alignment: .leading)
            TextField("Weight", value: weightBinding, format: weightFormat)
                .keyboardType(.decimalPad)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Weight in \(set.weightUnit.rawValue)")
            Text(set.weightUnit.rawValue)
                .foregroundStyle(.secondary)
            TextField("Reps", value: repsBinding, format: repsFormat)
                .keyboardType(.numberPad)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Reps")
            Text("reps")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.body)
    }
}
