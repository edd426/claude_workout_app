import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        List {
            musclesSection
            if !exercise.instructions.isEmpty {
                instructionsSection
            }
            metadataSection
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var musclesSection: some View {
        Section("Muscles") {
            if !exercise.primaryMuscles.isEmpty {
                LabeledContent("Primary", value: exercise.primaryMuscles.joined(separator: ", "))
            }
            if !exercise.secondaryMuscles.isEmpty {
                LabeledContent("Secondary", value: exercise.secondaryMuscles.joined(separator: ", "))
            }
        }
    }

    private var instructionsSection: some View {
        Section("Instructions") {
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(step)
                }
                .font(.body)
            }
        }
    }

    private var metadataSection: some View {
        Section("Details") {
            if let equipment = exercise.equipment {
                LabeledContent("Equipment", value: equipment)
            }
            if let level = exercise.level {
                LabeledContent("Level", value: level)
            }
            if let mechanic = exercise.mechanic {
                LabeledContent("Mechanic", value: mechanic)
            }
            if let force = exercise.force {
                LabeledContent("Force", value: force)
            }
        }
    }
}
