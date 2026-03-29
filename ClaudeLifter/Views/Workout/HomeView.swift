import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var vm: HomeViewModel?
    @State private var selectedTemplate: WorkoutTemplate? = nil
    @State private var showTemplateList = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.isWorkoutActive, let workoutId = appState.activeWorkoutId {
                    activeWorkoutView(workoutId: workoutId)
                } else {
                    templatePickerView
                }
            }
            .navigationTitle("ClaudeLifter")
        }
        .task {
            if vm == nil {
                vm = HomeViewModel(
                    templateRepository: SwiftDataTemplateRepository(context: modelContext)
                )
                await vm?.loadTemplates()
            }
        }
        .fullScreenCover(item: $selectedTemplate) { template in
            ActiveWorkoutView(
                vm: ActiveWorkoutViewModel(
                    template: template,
                    workoutRepository: SwiftDataWorkoutRepository(context: modelContext),
                    autoFillService: AutoFillService(
                        workoutRepository: SwiftDataWorkoutRepository(context: modelContext)
                    )
                )
            )
            .onDisappear { Task { await vm?.loadTemplates() } }
        }
    }

    private func activeWorkoutView(workoutId: UUID) -> some View {
        VStack {
            Text("Workout in progress")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var templatePickerView: some View {
        VStack(spacing: 0) {
            if let vm {
                if vm.templates.isEmpty {
                    emptyState(vm: vm)
                } else {
                    templateList(vm: vm)
                }
            } else {
                ProgressView()
            }
        }
    }

    private func emptyState(vm: HomeViewModel) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No templates yet")
                .font(.headline)
            Text("Create a template to start logging workouts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private func templateList(vm: HomeViewModel) -> some View {
        List(vm.templates, id: \.id) { template in
            Button {
                appState.startWorkout(id: UUID())
                selectedTemplate = template
            } label: {
                TemplateRowView(template: template)
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.loadTemplates() }
    }
}
