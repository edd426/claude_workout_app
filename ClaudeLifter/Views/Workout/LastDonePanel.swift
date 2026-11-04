import SwiftUI

/// The expanded "last done" panel on an active-workout exercise card (#167):
/// when this exercise was last done, with that session's sets, and when each
/// of its primary muscles was last trained, by which exercise. Collapsed by
/// default, so the card is no taller than before until it is asked for.
struct LastDonePanel: View {
    let recency: ExerciseRecency?
    let loadFailed: Bool

    var body: some View {
        Group {
            if let recency {
                LastDoneGrid(recency: recency, now: .now)
            } else if loadFailed {
                Text("Couldn't load your history.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Loading history…")
            }
        }
        // Last time is information needed between sets: at least
        // .subheadline (UI-Y3). No nested card background (UI-S2): the panel
        // sits under its toggle inside the exercise card.
        .font(.subheadline)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lastDonePanel")
    }
}

private struct LastDoneGrid: View {
    let recency: ExerciseRecency
    let now: Date

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                label("This exercise")
                sessionText
            }
            ForEach(recency.muscles, id: \.name) { muscle in
                GridRow {
                    label(muscle.name.capitalized)
                    muscleText(muscle)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private func when(_ date: Date?) -> String {
        let relative = ExerciseRecency.relativeDay(date, now: now, calendar: .current)
        guard let date else { return relative }
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.defaultDigits).day())
        return "\(relative) · \(day)"
    }

    @ViewBuilder
    private var sessionText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(when(recency.lastSession?.date))
            if let session = recency.lastSession {
                Text(ExerciseRecency.summary(of: session.sets))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func muscleText(_ muscle: ExerciseRecency.Muscle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let via = muscle.viaExercise {
                Text("\(when(muscle.lastTrained)) via \(via)")
            } else {
                Text(when(muscle.lastTrained))
            }
            Text(weeklyText(muscle.setsThisWeek))
                .foregroundStyle(.secondary)
        }
    }

    /// Finished workouts only: the session being logged is not counted.
    private func weeklyText(_ sets: Double) -> String {
        let count = sets.formatted(.number.precision(.fractionLength(0...1)))
        return "\(count) \(sets == 1 ? "set" : "sets") earlier this week"
    }
}
