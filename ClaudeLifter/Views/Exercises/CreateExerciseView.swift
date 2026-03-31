import SwiftUI
import SwiftData

struct CreateExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var vm = CreateExerciseViewModel()

    private let equipmentOptions = ["barbell", "dumbbell", "machine", "cable", "bodyweight", "kettlebell", "band", "smith_machine"]
    private let levelOptions = ["beginner", "intermediate", "advanced"]
    private let mechanicOptions = ["compound", "isolation"]
    private let forceOptions = ["push", "pull", "static"]
    private let muscleOptions = ["chest", "back", "shoulders", "biceps", "triceps", "quadriceps", "hamstrings", "glutes", "calves", "abs", "forearms"]

    var onSaved: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $vm.name)
                        .accessibilityIdentifier("exerciseName")
                }
                Section("Details") {
                    Picker("Equipment", selection: $vm.equipment) {
                        Text("None").tag("")
                        ForEach(equipmentOptions, id: \.self) { opt in
                            Text(opt.replacingOccurrences(of: "_", with: " ").capitalized).tag(opt)
                        }
                    }
                    Picker("Level", selection: $vm.level) {
                        Text("None").tag("")
                        ForEach(levelOptions, id: \.self) { opt in
                            Text(opt.capitalized).tag(opt)
                        }
                    }
                    Picker("Mechanic", selection: $vm.mechanic) {
                        Text("None").tag("")
                        ForEach(mechanicOptions, id: \.self) { opt in
                            Text(opt.capitalized).tag(opt)
                        }
                    }
                    Picker("Force", selection: $vm.force) {
                        Text("None").tag("")
                        ForEach(forceOptions, id: \.self) { opt in
                            Text(opt.capitalized).tag(opt)
                        }
                    }
                }
                Section("Primary Muscles") {
                    muscleMultiSelect
                }
                Section("Notes") {
                    TextField("Optional notes", text: $vm.notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let repo = SwiftDataExerciseRepository(context: modelContext)
                            try? await vm.save(using: repo)
                            onSaved?()
                            dismiss()
                        }
                    }
                    .disabled(!vm.canSave)
                    .accessibilityIdentifier("saveExercise")
                }
            }
        }
    }

    private var muscleMultiSelect: some View {
        ForEach(muscleOptions, id: \.self) { muscle in
            Button {
                if vm.primaryMuscles.contains(muscle) {
                    vm.primaryMuscles.removeAll { $0 == muscle }
                } else {
                    vm.primaryMuscles.append(muscle)
                }
            } label: {
                HStack {
                    Text(muscle.capitalized)
                        .foregroundStyle(.primary)
                    Spacer()
                    if vm.primaryMuscles.contains(muscle) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
        }
    }
}
