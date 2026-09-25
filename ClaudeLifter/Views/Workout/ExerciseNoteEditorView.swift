import SwiftUI

/// Which of an exercise's two notes is being edited.
enum ExerciseNoteKind {
    /// The library exercise's note — machine settings, shown in every workout
    /// containing the exercise (#136).
    case exercise
    /// This workout's copy of the template's note — the cue the Coach writes
    /// (reports 31A4983B, E26BBFAA). Offered back to the template at finish.
    case template
}

/// Edits the note attached to a library `Exercise` (#136), or this workout's
/// copy of the template's note for it.
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
    let kind: ExerciseNoteKind
    let onSave: (String?) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        exerciseName: String,
        initialNotes: String?,
        kind: ExerciseNoteKind = .exercise,
        onSave: @escaping (String?) -> Void
    ) {
        self.exerciseName = exerciseName
        self.initialNotes = initialNotes
        self.kind = kind
        self.onSave = onSave
        _text = State(initialValue: initialNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        placeholder,
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .focused($isFocused)
                    .accessibilityIdentifier("exerciseNoteField")
                    .accessibilityLabel(fieldLabel)
                } header: {
                    Text(exerciseName)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(title)
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

    private var title: String {
        switch kind {
        case .exercise: return "Note"
        case .template: return "Template Note"
        }
    }

    private var placeholder: String {
        switch kind {
        case .exercise: return "Seat 4; pin 7; pivot 1"
        case .template: return "Cue for this exercise"
        }
    }

    private var fieldLabel: String {
        switch kind {
        case .exercise: return "Exercise note"
        case .template: return "Template note"
        }
    }

    private var footer: String {
        switch kind {
        case .exercise:
            return "Machine settings and cues. Shown every time this exercise comes up, in any workout."
        case .template:
            return "Changes this workout's copy. When you finish, the summary offers to save it to the template."
        }
    }
}
