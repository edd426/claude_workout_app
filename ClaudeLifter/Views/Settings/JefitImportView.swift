import SwiftUI

/// Settings → Import Jefit History (#166): the dry run's plan, then Import.
/// Pushed inside the Settings sheet, never a sheet on a sheet (UI-P4).
struct JefitImportView: View {
    let fileURL: URL

    @Environment(\.dependencies) private var deps
    @Environment(\.dismiss) private var dismiss
    @State private var vm: JefitImportViewModel?

    var body: some View {
        Group {
            if let vm {
                JefitImportContent(vm: vm, onDone: { dismiss() })
            } else {
                ProgressView("Reading the Jefit export…")
            }
        }
        .navigationTitle("Jefit Import")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard vm == nil, let deps else { return }
            let model = JefitImportViewModel(
                service: makeService(deps),
                workoutRepository: deps.workoutRepository
            )
            vm = model
            await model.prepare(fileAt: fileURL)
        }
    }

    /// A missing mapping table can't happen in a built app; if it does, an
    /// empty table maps nothing and every name becomes a custom exercise,
    /// which the plan shows before anything is written.
    private func makeService(_ deps: DependencyContainer) -> JefitImportService {
        JefitImportService(
            exerciseRepository: deps.exerciseRepository,
            backupService: deps.backupService,
            mapTable: (try? JefitExerciseMapTable.bundled())
                ?? JefitExerciseMapTable(version: 0, catalog: [:], custom: [:])
        )
    }
}

private struct JefitImportContent: View {
    let vm: JefitImportViewModel
    let onDone: () -> Void

    var body: some View {
        switch vm.phase {
        case .idle, .preparing:
            ProgressView("Reading the Jefit export…")
        case .ready(let overview):
            JefitPlanList(overview: overview, isImporting: false, vm: vm, onDone: onDone)
        case .importing(let overview):
            JefitPlanList(overview: overview, isImporting: true, vm: vm, onDone: onDone)
        case .finished(let result):
            ContentUnavailableView {
                Label("Import finished", systemImage: "checkmark.circle")
            } description: {
                Text(result.message)
            } actions: {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .accessibilityIdentifier("jefitImportFinished")
        case .failed(let message):
            ContentUnavailableView {
                Label("Can't import this file", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Choose Another File", action: onDone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .accessibilityIdentifier("jefitImportFailed")
        }
    }
}

/// The dry run: what will be added, what attaches where, and what's left
/// out. The Import button sits at the bottom, in the thumb zone (UI-G5).
private struct JefitPlanList: View {
    let overview: JefitImportOverview
    let isImporting: Bool
    let vm: JefitImportViewModel
    let onDone: () -> Void

    var body: some View {
        List {
            workoutsSection
            Section("Exercises") {
                LabeledContent("Matched to your exercises", value: "\(overview.mappedExercises)")
                LabeledContent("New custom exercises", value: "\(overview.newCustomExercises)")
            }
            Section("Units") {
                Text(overview.unitSwitch.description)
            }
            if !overview.skipped.isEmpty {
                Section("Left out") {
                    ForEach(overview.skipped, id: \.self) { line in
                        Text(line)
                    }
                }
            }
        }
        .monospacedDigit()
        // On the List only: after the inset it also renamed the Import
        // button, so UI tests couldn't find it by its own identifier.
        .accessibilityIdentifier("jefitImportPlan")
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    private var workoutsSection: some View {
        Section {
            LabeledContent("Workouts", value: "\(overview.workouts)")
            LabeledContent("Sets", value: "\(overview.sets)")
            if let first = overview.firstWorkout, let last = overview.lastWorkout {
                LabeledContent("Dates", value: "\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
            }
            if overview.alreadyImported > 0 {
                LabeledContent("Already on this phone", value: "\(overview.alreadyImported)")
            }
        } header: {
            Text("Workouts")
        } footer: {
            Text(overview.newWorkouts == 0
                 ? "Every workout in this file is already on this phone, so importing adds nothing."
                 : "Imported workouts are tagged “\(JefitImportOptions.importNote)”. Nothing on this phone is changed or replaced.")
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 8) {
            if isImporting {
                ProgressView("Importing \(overview.newWorkouts) workouts…")
            } else if overview.newWorkouts == 0 {
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    Task { await vm.importPlan() }
                } label: {
                    Text("Import \(overview.newWorkouts) Workouts").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!vm.canImport)
                .accessibilityIdentifier("jefitImportConfirm")
            }
        }
        .padding(16)
        .background(.bar)
    }
}
