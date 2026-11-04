import SwiftUI

/// The Today tab (1.9.0). With no workout running it is one scrolling screen
/// (UI-P2): the hero (today's workout, or Resume), then at most four status
/// cards that each render only when they have something to say, then the
/// other templates. During a workout it hosts `ActiveWorkoutView`.
struct HomeView: View {
    @Environment(\.dependencies) private var deps
    @Environment(AppState.self) private var appState
    @State private var vm: HomeViewModel?
    @State private var bodyWeightVM: BodyWeightViewModel?
    @State private var bodyTrendVM: BodyWeightTrendViewModel?
    @State private var approvalVM: InboxApprovalViewModel?
    @State private var reportListVM: ReportListViewModel?
    @State private var showPendingChanges = false
    @State private var showTemplateEditor = false
    @State private var showReports = false
    @State private var showSettings = false
    /// Non-nil while the general (no-exercise) report sheet is up (A590AD71).
    @State private var generalReportContext: ReportContext?
    @State private var unreadInsights: [ProactiveInsight] = []
    @State private var path = NavigationPath()
    /// Launch runs both `.task` and the scene-phase handler; two finishers on
    /// one draft would each run PR detection on it.
    @State private var isAutoFinishingDrafts = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let activeVM = appState.activeWorkoutVM {
                    ActiveWorkoutView(vm: activeVM, onDismiss: {
                        // ActiveWorkoutView already calls appState.endWorkout() in its
                        // dismiss paths — here we only refresh Today.
                        Task { await vm?.loadToday() }
                    })
                } else {
                    todayScreen
                }
            }
            .navigationTitle("Today")
            .toolbar { todayToolbar }
        }
        .task { await setUpAndReload() }
        .modifier(TodayRefreshTriggers(
            onWorkoutEnded: { Task { await reloadAll() } },
            onBecameActive: { Task { await reloadOnReturn() } },
            onSynced: { Task { await reloadAfterSync() } },
            onApprovalsChanged: { approvalVM?.replaceApprovals($0) }
        ))
        .modifier(ApprovalErrorAlert(approvalVM: approvalVM))
        .modifier(TodaySheets(
            completedSummary: completedSummaryBinding,
            showSettings: $showSettings,
            showPendingChanges: $showPendingChanges,
            showReports: $showReports,
            showTemplateEditor: $showTemplateEditor,
            generalReportContext: $generalReportContext,
            approvalVM: approvalVM,
            reportListVM: reportListVM,
            onReload: { Task { await reloadAll() } },
            summarySheet: { summarySheet(for: $0) }
        ))
    }

    // MARK: - Screen

    @ViewBuilder
    private var todayScreen: some View {
        if let vm, vm.hasLoadedToday {
            ScrollView {
                if let deps {
                    // Surfaces the silent-no-op state from `SyncManager.syncIfNeeded`'s
                    // serverURL guard; renders nothing for every other state.
                    SyncStateBanner(state: deps.syncManager.state)
                }
                VStack(alignment: .leading, spacing: 16) {
                    errorBanner
                    hero(vm)
                    statusCards(vm)
                    templates(vm)
                    reportsLink
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            // Pull-to-refresh is the manual path; `TodayRefreshTriggers` is
            // the automatic one (UI-P7).
            .refreshable { await reloadAll() }
            .accessibilityIdentifier("todayScroll")
        } else {
            ProgressView("Loading today…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func hero(_ vm: HomeViewModel) -> some View {
        if let resumable = vm.resumableWorkout {
            ResumeWorkoutCard(
                workout: resumable,
                onResume: { resumeWorkout(resumable) },
                onDiscard: { Task { await vm.discardResumableWorkout() } }
            )
        } else if let template = vm.todaysTemplate {
            TodayHeroCard(
                template: template,
                isScheduledToday: vm.heroIsScheduledToday,
                subtitle: vm.heroSubtitle(for: template),
                onStart: { startWorkout(from: template) }
            )
        }
    }

    /// The card budget (UI-P2): four at most, none with nothing to say.
    @ViewBuilder
    private func statusCards(_ vm: HomeViewModel) -> some View {
        if let needsYou {
            NeedsYouCard(
                summary: needsYou,
                onReviewChanges: { showPendingChanges = true },
                onOpenReports: { showReports = true }
            )
        }
        if let volume = vm.weeklyVolume, volume.hasAnySets {
            WeeklyVolumeCard(volume: volume)
        }
        if let bodyLine {
            TodayBodyCard(line: bodyLine) { appState.show(.body) }
        }
        if !unreadInsights.isEmpty {
            TodayInsightSection(insights: unreadInsights) { await dismissInsight($0) }
        }
    }

    @ViewBuilder
    private func templates(_ vm: HomeViewModel) -> some View {
        if vm.templates.isEmpty {
            emptyState
        } else {
            OtherWorkoutsSection(
                templates: vm.otherTemplates,
                lastDone: { vm.lastDoneDate(for: $0) },
                onStart: { startWorkout(from: $0) },
                onStartEmpty: { startAdHocWorkout() },
                onNewTemplate: { showTemplateEditor = true }
            )
        }
    }

    /// Reports stay reachable when nothing is open: acknowledged ones still
    /// need resolving once their fix is installed (#154). A plain row, not a
    /// card, so it doesn't count against the budget.
    @ViewBuilder
    private var reportsLink: some View {
        if let reportListVM, !reportListVM.reports.isEmpty {
            Button { showReports = true } label: {
                HStack {
                    Label("Reports", systemImage: "flag")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(reportsDetail(reportListVM))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("openReportsCard")
        }
    }

    private func reportsDetail(_ reports: ReportListViewModel) -> String {
        let waiting = reports.acknowledgedCount
        return waiting > 0 ? "\(waiting) awaiting install" : "\(reports.reports.count) filed"
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No templates yet", systemImage: "dumbbell")
        } description: {
            Text("Create a template, or start an empty workout.")
        } actions: {
            Button("Start Empty Workout") { startAdHocWorkout() }
                .buttonStyle(.borderedProminent)
            Button("New Template") { showTemplateEditor = true }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = vm?.errorMessage ?? approvalLoadError {
            TodayCard {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandTheme.warning)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Button("Retry") { Task { await reloadAll() } }
                        .buttonStyle(.bordered)
                        .tint(Color(.systemGray))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("homeErrorBanner")
        }
    }

    /// A failed approvals check, inline rather than as an alert (UI-E1,
    /// UI-E3). Hidden when sync is off: `SyncStateBanner` already says so,
    /// and "not configured" is the expected failure then.
    private var approvalLoadError: String? {
        guard let message = approvalVM?.loadErrorMessage else { return nil }
        if case .disabled? = deps?.syncManager.state { return nil }
        return "Couldn't check for changes to approve. \(message)"
    }

    @ToolbarContentBuilder
    private var todayToolbar: some ToolbarContent {
        if appState.activeWorkoutVM == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gear")
                }
                .accessibilityIdentifier("settingsButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { generalReportContext = .general() } label: {
                    Label("Report a problem…", systemImage: "flag")
                }
                .accessibilityIdentifier("reportFromHome")
            }
        }
    }

    // MARK: - Derived rows

    private var needsYou: NeedsYouSummary? {
        NeedsYouSummary.make(
            pendingApprovals: approvalVM?.pendingCount ?? 0,
            openReports: reportListVM?.openCount ?? 0
        )
    }

    private var bodyLine: TodayBodyLine? {
        guard let bodyWeightVM,
              let entry = bodyWeightVM.latest,
              let weight = bodyWeightVM.latestDisplayWeight
        else { return nil }
        let now = Date.now
        return TodayBodyLine(
            text: TodayBodySummary.line(
                weight: weight,
                unit: bodyWeightVM.displayUnit,
                recordedAt: entry.recordedAt,
                status: bodyTrendVM?.goalStatus,
                goalPercentPerWeek: bodyTrendVM?.goalPercentPerWeek,
                now: now,
                calendar: .current
            ),
            isStale: TodayBodySummary.isStale(recordedAt: entry.recordedAt, now: now, calendar: .current)
        )
    }

    // MARK: - Loading

    private func setUpAndReload() async {
        guard let deps else { return }
        if vm == nil {
            vm = HomeViewModel(
                templateRepository: deps.templateRepository,
                workoutRepository: deps.workoutRepository
            )
        }
        if bodyWeightVM == nil {
            bodyWeightVM = BodyWeightViewModel(
                repository: deps.bodyWeightRepository,
                healthKit: deps.healthKitService,
                settings: deps.settings
            )
        }
        if bodyTrendVM == nil {
            bodyTrendVM = BodyWeightTrendViewModel(
                repository: deps.bodyWeightRepository,
                settings: deps.settings
            )
        }
        if reportListVM == nil {
            reportListVM = ReportListViewModel(repository: deps.exerciseReportRepository)
        }
        if approvalVM == nil {
            approvalVM = InboxApprovalViewModel(
                manager: deps.syncManager,
                previewBuilder: InboxChangePreviewBuilder(
                    templateRepository: deps.templateRepository,
                    exerciseRepository: deps.exerciseRepository,
                    alternativeRepository: deps.exerciseAlternativeRepository
                )
            )
        }
        await reloadAll()
        // Crash recovery (#75): an idle draft is finished, not offered.
        if !appState.isWorkoutActive {
            await autoFinishIdleDrafts()
        }
        // The weight card used to do this on Home; scale readings from
        // Health should still reach the Body row without opening Body.
        await bodyWeightVM?.importFromHealthKit()
    }

    private func reloadAll() async {
        await vm?.loadToday()
        await reportListVM?.load()
        await approvalVM?.load()
        await loadInsights()
        await bodyWeightVM?.load()
        await bodyTrendVM?.load()
    }

    /// A draft can cross the idle threshold while the app sits in the
    /// background on Today (report 07B1AD96), and the week or the day may
    /// have turned over.
    private func reloadOnReturn() async {
        guard !appState.isWorkoutActive else { return }
        await reloadAll()
        await autoFinishIdleDrafts()
    }

    /// An inbox apply can rename or edit templates and MCP can close reports,
    /// so a finished sync refreshes both (#100, #154).
    private func reloadAfterSync() async {
        guard !appState.isWorkoutActive else { return }
        await vm?.loadToday()
        await reportListVM?.load()
    }

    /// Honours the Settings toggle: with insights off, none are fetched.
    private func loadInsights() async {
        guard let deps, deps.settings.proactiveInsightsEnabled else {
            unreadInsights = []
            return
        }
        do {
            unreadInsights = try await deps.insightRepository.fetchUnread()
        } catch {
            // Keep whatever was showing; an insight is never essential (UI-E2).
        }
    }

    private func dismissInsight(_ insight: ProactiveInsight) async {
        guard let deps, let vm else { return }
        if await vm.dismissInsight(insight, using: deps.insightRepository) {
            unreadInsights.removeAll { $0.id == insight.id }
        }
    }

    // MARK: - Sheets

    private var completedSummaryBinding: Binding<WorkoutCompletionSummary?> {
        Binding(
            get: { appState.completedWorkoutSummary },
            set: { appState.completedWorkoutSummary = $0 }
        )
    }

    /// `summary` is @Observable, so both personalRecords and templateChangeSet
    /// appear when their post-commit work lands, even though the sheet is
    /// already on screen (#125, #130). Extracted from `body` because inlining
    /// it pushed the expression past the type-checker's budget.
    private func summarySheet(for summary: WorkoutCompletionSummary) -> some View {
        WorkoutSummaryView(
            workout: summary.workout,
            personalRecords: summary.personalRecords,
            onDismiss: { appState.completedWorkoutSummary = nil },
            templateChangeSet: summary.templateChangeSet,
            onApplyTemplateChanges: { changes in
                await applyTemplateChanges(changes, from: summary)
            },
            finishedAutomatically: summary.finishedAutomatically
        )
    }

    /// Applies the reviewed template changes (#130). Returns an error message
    /// to display, or nil on success — the workout is already saved, so a
    /// failure here costs a template update and nothing more.
    private func applyTemplateChanges(
        _ changes: [TemplateChange],
        from summary: WorkoutCompletionSummary
    ) async -> String? {
        guard let deps, let changeSet = summary.templateChangeSet else {
            return "Couldn't update the template. Your workout is saved."
        }
        do {
            try await TemplateChangeApplier(
                templateRepository: deps.templateRepository,
                exerciseRepository: deps.exerciseRepository
            ).apply(
                changes,
                from: changeSet,
                capturedRevision: changeSet.capturedRevision
            )
            await vm?.loadToday()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Starting and resuming

    private func startWorkout(from template: WorkoutTemplate) {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            template: template,
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            exerciseRepository: deps.exerciseRepository,
            templateRepository: deps.templateRepository,
            baselineRepository: deps.baselineRepository,
            prDetectionService: deps.prDetectionService,
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
        let workoutVM = makeResumedWorkoutVM(for: workout, deps: deps)
        path = NavigationPath()
        vm?.resumableWorkout = nil
        appState.startWorkout(id: workout.id, vm: workoutVM)
    }

    private func makeResumedWorkoutVM(
        for workout: Workout,
        deps: DependencyContainer
    ) -> ActiveWorkoutViewModel {
        ActiveWorkoutViewModel(
            resuming: workout,
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            exerciseRepository: deps.exerciseRepository,
            templateRepository: deps.templateRepository,
            baselineRepository: deps.baselineRepository,
            prDetectionService: deps.prDetectionService,
            settings: deps.settings
        )
    }

    /// A draft left open past the idle threshold — force-quit mid-workout, or
    /// "Save progress as draft" and never resumed — is finished instead of
    /// being offered for Resume (report 07B1AD96). It is finished through a
    /// resumed `ActiveWorkoutViewModel`, so it is the same finish as a Finish
    /// tap, and its receipt is presented over Today saying it was automatic.
    ///
    /// One draft per pass: only one receipt can be on screen, and a second
    /// would replace the first unseen. Any older idle draft surfaces on the
    /// Resume card and is finished on the next launch or return to the app.
    private func autoFinishIdleDrafts() async {
        guard let deps, let vm, !isAutoFinishingDrafts else { return }
        isAutoFinishingDrafts = true
        defer { isAutoFinishingDrafts = false }
        guard
            !appState.isWorkoutActive,
            let draft = vm.resumableWorkout,
            WorkoutAutoFinishPolicy.window(for: draft, now: .now) != nil
        else { return }
        let finisher = makeResumedWorkoutVM(for: draft, deps: deps)
        guard
            await finisher.autoFinishIfIdle(),
            case .finished(let summary) = finisher.completionState
        else { return }
        // The finisher is local, and its post-commit task holds it weakly:
        // released first, PR detection and template review would silently
        // not run. Nobody is waiting on a tap here, so wait for them.
        await finisher.awaitPostCommitWork()
        appState.completedWorkoutSummary = summary
        await vm.loadToday()
    }

    private func startAdHocWorkout() {
        guard let deps else { return }
        let workoutVM = ActiveWorkoutViewModel(
            adHocName: "Quick Workout",
            workoutRepository: deps.workoutRepository,
            autoFillService: deps.autoFillService,
            exerciseRepository: deps.exerciseRepository,
            prDetectionService: deps.prDetectionService,
            settings: deps.settings
        )
        path = NavigationPath()
        let workoutId = UUID()
        appState.startWorkout(id: workoutId, vm: workoutVM)
    }
}
