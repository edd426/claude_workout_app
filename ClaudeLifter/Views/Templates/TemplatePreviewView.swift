import SwiftUI

struct TemplatePreviewView: View {
    let template: WorkoutTemplate
    let onStartWorkout: () -> Void

    @State private var showEditor = false
    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss

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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(te.exercise?.name ?? "Unknown")
                            .font(.body)
                        Text("\(te.defaultSets) sets × \(te.defaultReps) reps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        // Start lives in a bottom bar, in the thumb zone (UI-G5), so a long
        // note or a nine-exercise template never pushes it off-screen.
        .safeAreaInset(edge: .bottom) { startBar }
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
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

    private var startBar: some View {
        Button {
            // Pop back to Today BEFORE starting the workout so the root-level
            // swap to ActiveWorkoutView is actually visible (otherwise this
            // pushed preview shadows the swap and the button appears dead).
            dismiss()
            onStartWorkout()
        } label: {
            Label("Start Workout", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityIdentifier("startWorkoutFromPreview")
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
