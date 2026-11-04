import SwiftUI

/// A template in a list: its name, then exercise count and when it was last
/// done. `lastDone` is derived from finished workouts (#176), never read
/// from the stored `lastPerformedAt`, which some finish paths leave stale.
struct TemplateRowView: View {
    let template: WorkoutTemplate
    let lastDone: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        TodayTemplatePicker.subtitle(
            exerciseCount: template.exercises.count,
            lastDone: lastDone,
            now: .now,
            calendar: .current
        )
    }
}
