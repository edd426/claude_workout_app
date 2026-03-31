import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @State private var vm: HomeViewModel?
    @State private var selectedTemplate: WorkoutTemplate? = nil
    @State private var showTemplateEditor = false
    @State private var showAdHocWorkout = false
    @State private var unreadInsights: [ProactiveInsight] = []

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
                    templateRepository: SwiftDataTemplateRepository(context: modelContext),
                    workoutRepository: SwiftDataWorkoutRepository(context: modelContext)
                )
                await vm?.loadTemplates()
            }
            let insightRepo = SwiftDataInsightRepository(context: modelContext)
            if let fetched = try? await insightRepo.fetchUnread() {
                unreadInsights = fetched
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
        .fullScreenCover(isPresented: $showAdHocWorkout) {
            ActiveWorkoutView(
                vm: ActiveWorkoutViewModel(
                    adHocName: "Quick Workout",
                    workoutRepository: SwiftDataWorkoutRepository(context: modelContext),
                    autoFillService: AutoFillService(
                        workoutRepository: SwiftDataWorkoutRepository(context: modelContext)
                    )
                )
            )
        }
        .sheet(isPresented: $showTemplateEditor) {
            TemplateEditorView(
                vm: TemplateEditorViewModel(
                    template: nil,
                    templateRepository: SwiftDataTemplateRepository(context: modelContext)
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
            if !unreadInsights.isEmpty {
                insightCardsSection
            }
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

    private var insightCardsSection: some View {
        VStack(spacing: 8) {
            ForEach(unreadInsights, id: \.id) { insight in
                InsightCardView(insight: insight) {
                    let insightRepo = SwiftDataInsightRepository(context: modelContext)
                    try? await insightRepo.markAsRead(insight)
                    unreadInsights.removeAll { $0.id == insight.id }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func emptyState(vm: HomeViewModel) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dumbbell")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No templates yet")
                .font(.headline)
            Text("Create a template or start an empty workout.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actionButtons
            Spacer()
        }
        .padding()
    }

    private func templateList(vm: HomeViewModel) -> some View {
        List {
            ForEach(vm.templates, id: \.id) { template in
                Button {
                    appState.startWorkout(id: UUID())
                    selectedTemplate = template
                } label: {
                    TemplateRowView(template: template)
                }
            }
            Section {
                actionButtons
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.loadTemplates() }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                showAdHocWorkout = true
            } label: {
                Label("Start Empty Workout", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showTemplateEditor = true
            } label: {
                Label("New Template", systemImage: "plus.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            NavigationLink {
                TemplateListView()
            } label: {
                Label("Manage Templates", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }
}
