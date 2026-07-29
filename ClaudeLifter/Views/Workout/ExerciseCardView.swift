import SwiftUI

struct ExerciseCardView: View {
    let workoutExercise: WorkoutExercise
    let focusedField: FocusState<SetEntryFieldID?>.Binding
    let previousValue: (WorkoutSet) -> AutoFillResult?
    let onCompleteSet: (WorkoutSet) -> Void
    let onEditWeight: (WorkoutSet, Double?) -> Void
    let onEditReps: (WorkoutSet, Int?) -> Void
    let onAddSet: () -> Void
    var onRemoveSet: ((WorkoutSet) -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted(by: { $0.order < $1.order })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            exerciseHeader
            Divider()
            setEntryRows
            addSetButton
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var setEntryRows: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(sortedSets, id: \.id) { set in
                    setRow(set, layout: .stacked)
                        .id(set.id)
                }
            }
        } else {
            Grid(horizontalSpacing: 8, verticalSpacing: 2) {
                columnHeaders
                ForEach(sortedSets, id: \.id) { set in
                    setRow(set, layout: .compact)
                        .id(set.id)
                }
            }
        }
    }

    private func setRow(
        _ set: WorkoutSet,
        layout: SetRowLayout
    ) -> some View {
        SetRowView(
            workoutExerciseID: workoutExercise.id,
            set: set,
            previous: previousValue(set),
            layout: layout,
            focusedField: focusedField,
            onComplete: onCompleteSet,
            onEditWeight: onEditWeight,
            onEditReps: onEditReps
        )
    }

    private var columnHeaders: some View {
        GridRow {
            headerText("SET", alignment: .leading)
            headerText("PREVIOUS", alignment: .trailing)
            headerText("WEIGHT", alignment: .trailing)
            headerText("REPS", alignment: .trailing)
            Color.clear
                .frame(width: 44, height: 1)
                .accessibilityHidden(true)
        }
    }

    private func headerText(
        _ title: String,
        alignment: HorizontalAlignment
    ) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(alignment)
    }

    private var addSetButton: some View {
        Button(action: onAddSet) {
            Label("Add Set", systemImage: "plus.circle")
                .font(.caption)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .padding(.top, 4)
    }

    private var exerciseHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workoutExercise.exercise?.name ?? "Unknown Exercise")
                    .font(.headline)
                if let muscles = workoutExercise.exercise?.primaryMuscles,
                   !muscles.isEmpty {
                    Text(muscles.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            removeSetMenu
        }
    }

    @ViewBuilder
    private var removeSetMenu: some View {
        if sortedSets.count > 1, let onRemoveSet {
            Menu {
                Section("Remove Set…") {
                    ForEach(sortedSets, id: \.id) { set in
                        Button("Set \(set.order + 1)", role: .destructive) {
                            onRemoveSet(set)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Exercise actions")
        }
    }
}
