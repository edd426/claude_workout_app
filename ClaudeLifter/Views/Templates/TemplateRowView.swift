import SwiftUI

struct TemplateRowView: View {
    let template: WorkoutTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(template.name)
                .font(.headline)
            HStack {
                Text("\(template.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastPerformed = template.lastPerformedAt {
                    Text("· Last: \(lastPerformed.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
