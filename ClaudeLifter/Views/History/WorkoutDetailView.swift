import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout
    var onSave: ((@MainActor (Workout) async -> Void))? = nil

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
                        if isEditing {
                            WorkoutSetEditRow(set: set)
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
            if onSave != nil {
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
                Text(String(format: "%.1f %@", weight, set.weightUnit.rawValue))
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

    @State private var weightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(set.order + 1)")
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            TextField("Weight", text: $weightText)
                .keyboardType(.decimalPad)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
            Text(set.weightUnit.rawValue)
                .foregroundStyle(.secondary)
            TextField("Reps", text: $repsText)
                .keyboardType(.numberPad)
                .frame(width: 50)
                .textFieldStyle(.roundedBorder)
            Text("reps")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .font(.body)
        .onAppear {
            weightText = set.weight.map { String(format: "%.1f", $0) } ?? ""
            repsText = set.reps.map { String($0) } ?? ""
        }
        .onChange(of: weightText) {
            if let value = Double(weightText) {
                set.weight = value
            }
        }
        .onChange(of: repsText) {
            if let value = Int(repsText) {
                set.reps = value
            }
        }
    }
}
