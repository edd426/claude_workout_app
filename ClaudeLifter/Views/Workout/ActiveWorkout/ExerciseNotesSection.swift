import SwiftUI

/// The two notes an exercise card can carry (#136).
enum ExerciseNotes {
    static func cleaned(_ value: String?) -> String? {
        guard
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }

    /// This workout's copy of the template's cue, unless it only repeats the
    /// machine note.
    @MainActor
    static func session(of workoutExercise: WorkoutExercise) -> String? {
        let session = cleaned(workoutExercise.notes)
        return session == cleaned(workoutExercise.exercise?.notes) ? nil : session
    }
}

/// The machine note in full, and the template cue collapsed to one line.
///
/// The user's own note is shown unconditionally when present: a note behind a
/// tap is a note you do not read mid-set, which is the whole of #136. The
/// template note is the opposite case (report 31A4983B): long Coach prose
/// that crowded the card, so it gets one line until tapped.
struct ExerciseNotesSection: View {
    let exerciseNotes: String?
    let sessionNotes: String?
    @Binding var isTemplateNoteExpanded: Bool
    let onEditNotes: () -> Void
    let onEditTemplateNote: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if exerciseNotes != nil || sessionNotes != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let exerciseNotes {
                    machineNote(exerciseNotes)
                }
                if let sessionNotes {
                    templateNote(sessionNotes)
                }
            }
        }
    }

    /// Machine settings, at `.callout` in primary: needed standing at the
    /// machine (UI-Y3). One tap opens the editor.
    private func machineNote(_ text: String) -> some View {
        Button(action: onEditNotes) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Note: \(text)")
        .accessibilityHint("Edit this note")
        .accessibilityIdentifier("exerciseNotes")
    }

    private func templateNote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { isTemplateNoteExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text(text)
                        .lineLimit(isTemplateNoteExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: isTemplateNoteExpanded ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Template note: \(text)")
            .accessibilityValue(isTemplateNoteExpanded ? "expanded" : "collapsed")
            .accessibilityIdentifier("sessionNotes")

            if isTemplateNoteExpanded {
                Button("Edit template note", action: onEditTemplateNote)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("editTemplateNote")
            }
        }
    }
}
