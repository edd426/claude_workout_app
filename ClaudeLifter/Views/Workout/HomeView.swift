import SwiftUI

struct HomeView: View {
    @Environment(\.dependencies) private var deps
    @Environment(AppState.self) private var appState
    @State private var vm: HomeViewModel?
    @State private var showTemplateEditor = false
    @State private var unreadInsights: [ProactiveInsight] = []

    var body: some View {
        NavigationStack {
            Group {
                if let activeVM = appState.activeWorkoutVM {
                    ActiveWorkoutView(vm: activeVM, onDismiss: {
                        appState.endWorkout()
                        Task { await vm?.loadTemplates() }
                    })
                } else {
                    templatePickerView
                }
            }
            .navigationTitle("ClaudeLifter")
        }
        .task {
            guard let deps else { return }
            if vm == nil {
                vm = HomeViewModel(
                    templateRepository: deps.templateRepository,
                    workoutRepository: deps.workoutRepository
                )
                await vm?.loadTemplates()
            }
            if let fetched = try? await deps.insightRepository.fetchUnread() {
                unreadInsights = fetched
            }
        }
        .onAppear {
            Task { await vm?.loadTemplates() }
        }
        .sheet(isPresented: $showTemplateEditor) {
            if let deps {
                TemplateEditorView(
                    vm: TemplateEditorViewModel(
                        template: nil,
                        templateRepository: deps.templateRepository
                    )
                )
                .onDisappear { Task { await vm?.loadTemplates() } }
            }
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
                    try? await deps?.insightRepository.markAsRead(insight)
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
                NavigationLink {
                    TemplatePreviewView(template: template) {
                        startWorkout(from: template)
                    }
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

    private func startWorkout(from template: WorkoutTemplate) {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            templateRepository: deps.templateRepository
        )
        let workoutId = UUID()
        appState.startWorkout(id: workoutId, vm: workoutVM)
    }

    private func startAdHocWorkout() {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService
        )
        let workoutId = UUID()
        appState.startWorkout(id: workoutId, vm: workoutVM)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                startAdHocWorkout()
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
