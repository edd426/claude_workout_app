import SwiftUI

struct TemplatePreviewView: View {
    let template: WorkoutTemplate
    let onStartWorkout: () -> Void

    @State private var showEditor = false
    @Environment(\.dependencies) private var deps

    private var sortedExercises: [TemplateExercise] {
        template.exercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            if let notes = template.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Exercises") {
                ForEach(sortedExercises, id: \.id) { te in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(te.exercise?.name ?? "Unknown")
                            .font(.body)
                        Text("\(te.defaultSets) sets × \(te.defaultReps) reps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button {
                    onStartWorkout()
                } label: {
                    Text("Start Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("startWorkoutFromPreview")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(.init())
        }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            if let deps {
                TemplateEditorView(
                    vm: TemplateEditorViewModel(
                        template: template,
                        templateRepository: deps.templateRepository
                    )
                )
            }
        }
    }
}
