import SwiftUI
import SwiftData

struct TemplatePreviewView: View {
    let template: WorkoutTemplate
    let onStartWorkout: () -> Void

    @State private var showEditor = false
    @Environment(\.modelContext) private var modelContext

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
            TemplateEditorView(
                vm: TemplateEditorViewModel(
                    template: template,
                    templateRepository: SwiftDataTemplateRepository(context: modelContext)
                )
            )
        }
    }
}
