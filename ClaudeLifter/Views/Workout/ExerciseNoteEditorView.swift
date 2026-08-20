import SwiftUI

/// Edits the note attached to a library `Exercise` (#136).
///
/// The note describes the machine — "Ankle 4; Seat 4; Pivot 1" — so it belongs
/// to the exercise, not to this session or this template. Every future workout
/// containing the exercise shows it, whichever template it came from.
///
/// A sheet rather than an inline field: the workout screen owns a single
/// `@FocusState` keyed on `SetEntryFieldID` with a keyboard accessory bar for
/// weight/reps navigation, and a free-text field in that hierarchy would have
/// to join or fight it.
struct ExerciseNoteEditorView: View {
    let exerciseName: String
    let initialNotes: String?
    let onSave: (String?) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        exerciseName: String,
        initialNotes: String?,
        onSave: @escaping (String?) -> Void
    ) {
        self.exerciseName = exerciseName
        self.initialNotes = initialNotes
        self.onSave = onSave
        _text = State(initialValue: initialNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Seat 4; pin 7; pivot 1",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .focused($isFocused)
                    .accessibilityIdentifier("exerciseNoteField")
                    .accessibilityLabel("Exercise note")
                } header: {
                    Text(exerciseName)
                } footer: {
                    Text("Machine settings and cues. Shown every time this exercise comes up, in any workout.")
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveExerciseNote")
                }
            }
            .task { isFocused = true }
        }
    }
}
