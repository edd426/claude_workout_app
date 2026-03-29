import SwiftUI

struct ExerciseRowView: View {
    let exercise: Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.body)
            HStack(spacing: 8) {
                if let muscles = exercise.primaryMuscles.first {
                    Label(muscles, systemImage: "figure.strengthtraining.traditional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let equipment = exercise.equipment {
                    Text("· \(equipment)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
