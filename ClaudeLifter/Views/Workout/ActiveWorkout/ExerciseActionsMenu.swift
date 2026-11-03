import SwiftUI

/// The card's visible `•••` menu (UI-P7: nothing here is swipe-only).
///
/// At most seven items in sections, destructive last (UI-P8, UI-P6): note,
/// template note, report; move; skip; remove a set; remove the exercise.
struct ExerciseActionsMenu: View {
    let vm: ActiveWorkoutViewModel
    let workoutExercise: WorkoutExercise
    let actions: ExerciseCardActions

    private var sortedSets: [WorkoutSet] {
        workoutExercise.sets.sorted { $0.order < $1.order }
    }

    var body: some View {
        Menu {
            Section {
                Button(action: actions.onEditNotes) {
                    Label(
                        ExerciseNotes.cleaned(workoutExercise.exercise?.notes) == nil
                            ? "Add a note…" : "Edit note…",
                        systemImage: "note.text"
                    )
                }
                .accessibilityIdentifier("editExerciseNotes")
                if ExerciseNotes.session(of: workoutExercise) != nil {
                    Button(action: actions.onEditTemplateNote) {
                        Label("Edit template note…", systemImage: "text.bubble")
                    }
                    .accessibilityIdentifier("editTemplateNoteMenu")
                }
                Button(action: actions.onReport) {
                    Label("Report a problem…", systemImage: "flag")
                }
                .accessibilityIdentifier("reportExercise")
            }
            Section {
                moveMenu
                skipButton
            }
            Section {
                removeSetMenu
                Button(role: .destructive, action: actions.onRemoveExercise) {
                    Label("Remove from this workout", systemImage: "trash")
                }
                .accessibilityIdentifier("removeExercise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 56)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Exercise actions")
        .accessibilityIdentifier("exerciseActions")
    }

    @ViewBuilder
    private var moveMenu: some View {
        let canUp = vm.canMove(workoutExercise, by: -1)
        let canDown = vm.canMove(workoutExercise, by: 1)
        if canUp || canDown {
            Menu {
                Button {
                    vm.moveExercise(workoutExercise, by: -1)
                } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                .disabled(!canUp)
                Button {
                    vm.moveExercise(workoutExercise, by: 1)
                } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                .disabled(!canDown)
            } label: {
                Label("Move", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityIdentifier("moveExercise")
        }
    }

    @ViewBuilder
    private var skipButton: some View {
        if vm.isSkipped(workoutExercise) {
            Button {
                vm.expand(workoutExercise)
            } label: {
                Label("Do it after all", systemImage: "arrow.uturn.backward")
            }
            .accessibilityIdentifier("unskipExercise")
        } else if vm.canSkip(workoutExercise) {
            Button {
                vm.skip(workoutExercise)
            } label: {
                Label("Skip today", systemImage: "forward.end")
            }
            .accessibilityIdentifier("skipExercise")
        }
    }

    @ViewBuilder
    private var removeSetMenu: some View {
        if sortedSets.count > 1 {
            Menu {
                ForEach(sortedSets, id: \.id) { set in
                    Button("Set \(set.order + 1)", role: .destructive) {
                        actions.onRemoveSet(set)
                    }
                }
            } label: {
                Label("Remove Set…", systemImage: "minus.circle")
            }
            .accessibilityIdentifier("removeSetMenu")
        }
    }
}
