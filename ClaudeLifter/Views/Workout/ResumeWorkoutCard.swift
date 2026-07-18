import SwiftUI

/// Home-screen prompt for an in-progress workout left behind by a crash,
/// force-quit, or "Save progress as draft" (issue #75). Resume restores the
/// session with all logged sets; Discard deletes it — but only after an
/// explicit confirmation, never silently.
struct ResumeWorkoutCard: View {
    let workout: Workout
    let onResume: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardConfirmation = false

    private var completedSetCount: Int {
        workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(BrandTheme.terracotta)
                Text("Workout in progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            summaryLine
            buttonRow
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard \"\(workout.name)\"", role: .destructive) {
                onDiscard()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This permanently deletes the session and its \(completedSetCount) logged set(s).")
        }
    }

    private var summaryLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(workout.name)
                .font(.headline)
            Text("\(completedSetCount) set\(completedSetCount == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(workout.startedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            Button {
                onResume()
            } label: {
                Label("Resume", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTheme.terracotta)
            .accessibilityIdentifier("resumeWorkout")

            Button(role: .destructive) {
                showDiscardConfirmation = true
            } label: {
                Text("Discard")
                    .frame(maxWidth: 100)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("discardResumableWorkout")
        }
    }
}
