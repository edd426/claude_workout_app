import SwiftUI

struct HomeView: View {
    @Environment(\.dependencies) private var deps
    @Environment(AppState.self) private var appState
    @State private var vm: HomeViewModel?
    @State private var bodyWeightVM: BodyWeightViewModel?
    @State private var showTemplateEditor = false
    @State private var unreadInsights: [ProactiveInsight] = []
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let activeVM = appState.activeWorkoutVM {
                    ActiveWorkoutView(vm: activeVM, onDismiss: {
                        // ActiveWorkoutView already calls appState.endWorkout() in its
                        // dismiss paths — here we only refresh templates.
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
            // Crash recovery (#75): surface any in-progress workout left
            // behind by a crash, force-quit, or explicit draft save.
            if !appState.isWorkoutActive {
                await vm?.checkForResumableWorkout()
            }
            if bodyWeightVM == nil {
                bodyWeightVM = BodyWeightViewModel(
                    repository: deps.bodyWeightRepository,
                    healthKit: deps.healthKitService,
                    settings: deps.settings
                )
            }
            // Honour the user's Settings toggle — don't even fetch insight
            // cards if they're disabled. Prevents a "pile up after weeks
            // away" cluttered Home screen.
            if deps.settings.proactiveInsightsEnabled,
               let fetched = try? await deps.insightRepository.fetchUnread() {
                unreadInsights = fetched
            } else {
                unreadInsights = []
            }
        }
        // Refresh templates when an active workout ends (replaces the old
        // double-call of loadTemplates from .task + .onAppear).
        .onChange(of: appState.isWorkoutActive) { wasActive, isActive in
            if wasActive && !isActive {
                Task {
                    await vm?.loadTemplates()
                    // A workout just ended — a saved draft (Exit → "Save
                    // progress as draft") becomes resumable right away (#75).
                    await vm?.checkForResumableWorkout()
                }
            }
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
            if let deps {
                // Surfaces the silent-no-op state from `SyncManager.syncIfNeeded`'s
                // serverURL guard. Rendered as a no-op for every other state, so
                // the configured-and-working case adds no chrome here.
                SyncStateBanner(state: deps.syncManager.state)
            }
            if let vm, let resumable = vm.resumableWorkout {
                ResumeWorkoutCard(
                    workout: resumable,
                    onResume: { resumeWorkout(resumable) },
                    onDiscard: { Task { await vm.discardResumableWorkout() } }
                )
            }
            if let bodyWeightVM {
                BodyWeightCard(vm: bodyWeightVM)
            }
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
            templateRepository: deps.templateRepository,
            settings: deps.settings
        )
        // Clear any pushed navigation (e.g. TemplatePreviewView) so the root
        // swap to ActiveWorkoutView is actually visible to the user. Without
        // this, tapping Start Workout from a pushed preview did nothing.
        path = NavigationPath()
        let workoutId = UUID()
        appState.startWorkout(id: workoutId, vm: workoutVM)
    }

    /// Crash recovery (#75): re-adopts an in-progress workout as the active
    /// session with all logged sets intact.
    private func resumeWorkout(_ workout: Workout) {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            templateRepository: deps.templateRepository,
            settings: deps.settings
        )
        path = NavigationPath()
        vm?.resumableWorkout = nil
        appState.startWorkout(id: workout.id, vm: workoutVM)
    }

    private func startAdHocWorkout() {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            settings: deps.settings
        )
        path = NavigationPath()
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
