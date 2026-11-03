import SwiftUI

/// Today's hero while an in-progress workout is waiting: one left behind by a
/// crash, force-quit, or "Save progress as draft" (issue #75). Resume restores
/// the session with all logged sets and is the screen's only tinted button
/// (UI-P1, UI-T2). Discard deletes it, but only after an explicit
/// confirmation, never silently (UI-P6).
struct ResumeWorkoutCard: View {
    let workout: Workout
    let onResume: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardConfirmation = false
    @State private var discardConfirmed = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var completedSetCount: Int {
        workout.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                summary
                buttonRow
            }
        }
        .accessibilityIdentifier("resumeWorkoutCard")
        .sensoryFeedback(.warning, trigger: discardConfirmed)
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard \"\(workout.name)\"", role: .destructive) {
                discardConfirmed += 1
                onDiscard()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This permanently deletes the session and its \(completedSetCount) logged set(s).")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Workout in progress", systemImage: "arrow.counterclockwise.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BrandTheme.accentText)
            Text(workout.name)
                .font(.headline)
            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        let sets = "\(completedSetCount) set\(completedSetCount == 1 ? "" : "s") logged"
        let started = workout.startedAt.formatted(.relative(presentation: .named))
        return "\(sets) · started \(started)"
    }

    @ViewBuilder
    private var buttonRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) { resumeButton; discardButton }
        } else {
            HStack(spacing: 12) { resumeButton; discardButton }
        }
    }

    private var resumeButton: some View {
        Button(action: onResume) {
            Label("Resume", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityIdentifier("resumeWorkout")
    }

    private var discardButton: some View {
        Button(role: .destructive) {
            showDiscardConfirmation = true
        } label: {
            Text("Discard")
                .font(.headline)
                // System red, never the app tint (UI-P6), on a gray bezel so
                // only Resume has a tinted background (UI-P1).
                .foregroundStyle(BrandTheme.destructive)
                .frame(minWidth: 88, minHeight: 44)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .tint(Color(.systemGray))
        .accessibilityIdentifier("discardResumableWorkout")
    }
}
