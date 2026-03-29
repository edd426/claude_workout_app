import SwiftUI

struct TemplateEditorView: View {
    @State var vm: TemplateEditorViewModel
    @State private var showExercisePicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                templateNameSection
                exercisesSection
            }
            .navigationTitle(vm.isNew ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showExercisePicker) {
                ExerciseLibraryView(selectionMode: true) { exercise in
                    vm.addExercise(exercise)
                }
            }
            .alert("Error", isPresented: .constant(vm.validationError != nil)) {
                Button("OK") { vm.validationError = nil }
            } message: {
                Text(vm.validationError ?? "")
            }
            .onChange(of: vm.isSaved) { _, saved in
                if saved { dismiss() }
            }
        }
    }

    private var templateNameSection: some View {
        Section("Template Name") {
            TextField("e.g. Wednesday Push Day", text: $vm.name)
        }
    }

    private var exercisesSection: some View {
        Section("Exercises") {
            ForEach(vm.exercises, id: \.id) { te in
                TemplateExerciseRowView(templateExercise: te)
            }
            .onDelete { vm.removeExercise(at: $0) }
            .onMove { vm.moveExercise(from: $0, to: $1) }
            Button("Add Exercise") { showExercisePicker = true }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                Task { await vm.save() }
            }
        }
    }
}

private struct TemplateExerciseRowView: View {
    let templateExercise: TemplateExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(templateExercise.exercise?.name ?? "Unknown")
                .font(.body)
            Text("\(templateExercise.defaultSets) sets × \(templateExercise.defaultReps) reps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
