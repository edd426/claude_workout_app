import SwiftUI

/// The overview strip pinned under the nav bar: one chip per exercise
/// ("Squat 1/3", "RDL 3/3 ✓"). He picks the next exercise by which machine
/// is free, so what's done and what's left must be one glance, and any
/// exercise one tap away (UI-G2).
struct ExerciseStripView: View {
    let vm: ActiveWorkoutViewModel
    let onSelect: (WorkoutExercise) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.orderedExercises, id: \.id) { workoutExercise in
                        ExerciseStripChip(
                            name: workoutExercise.exercise?.name ?? "Exercise",
                            progress: vm.progress(for: workoutExercise),
                            isExpanded: vm.isExpanded(workoutExercise)
                        ) {
                            onSelect(workoutExercise)
                        }
                        .id(workoutExercise.id)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            // The open exercise's chip stays in view, however long the list.
            .onChange(of: vm.expandedExerciseId) { _, open in
                guard let open else { return }
                withAnimation(reduceMotion ? nil : .snappy) {
                    proxy.scrollTo(open, anchor: .center)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exercises")
        .accessibilityIdentifier("exerciseStrip")
    }
}

private struct ExerciseStripChip: View {
    let name: String
    let progress: ExerciseProgress
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                    .lineLimit(1)
                    .strikethrough(progress.status == .skipped)
                // The count never truncates; a long name does.
                Text(countText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                if progress.status == .finished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BrandTheme.completed)
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline)
            .foregroundStyle(progress.status == .skipped ? .secondary : .primary)
            .frame(maxWidth: 170)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(background, in: Capsule())
            .overlay {
                if isExpanded {
                    Capsule().strokeBorder(BrandTheme.accent, lineWidth: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(progress.completedSets) of \(progress.totalSets) sets")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens this exercise")
        .accessibilityIdentifier("stripChip_\(name)")
    }

    private var countText: String {
        progress.status == .skipped ? "skipped" : "\(progress.completedSets)/\(progress.totalSets)"
    }

    private var background: Color {
        progress.status == .finished
            ? BrandTheme.completed.opacity(0.14)
            : Color(uiColor: .secondarySystemFill)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        switch progress.status {
        case .finished: parts.append("done")
        case .skipped: parts.append("skipped")
        case .inProgress, .untouched: break
        }
        if isExpanded { parts.append("open") }
        return parts.joined(separator: ", ")
    }
}
