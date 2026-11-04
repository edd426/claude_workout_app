import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    let dependencies: DependencyContainer

    @State private var chatViewModel: ChatViewModel?

    var body: some View {
        @Bindable var appState = appState
        // Five tabs, the iPhone limit. Settings is a sheet from the gear in
        // Today's toolbar (1.9.0 IA).
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { tabLabel(.today) }
                .tag(AppTab.today)

            HistoryListView()
                .tabItem { tabLabel(.history) }
                .tag(AppTab.history)

            BodyView()
                .tabItem { tabLabel(.body) }
                .tag(AppTab.body)

            ExerciseLibraryView()
                .tabItem { tabLabel(.exercises) }
                .tag(AppTab.exercises)

            coachTab
                .tabItem { tabLabel(.coach) }
                .tag(AppTab.coach)
        }
        // The app tint is the brand accent. Destructive controls set
        // `BrandTheme.destructive` themselves where the tint would otherwise
        // win (swipe actions, bordered buttons), so they stay system red
        // (UI-P6).
        // accentText, not accent: the tint colours toolbar and link text at
        // body size, where brand terracotta is 3.1:1 on white (UI-C3). Fills
        // that need the brand colour set BrandTheme.accent themselves.
        .tint(BrandTheme.accentText)
        .task {
            if chatViewModel == nil {
                chatViewModel = ChatViewModel(
                    anthropicService: dependencies.anthropicService,
                    exerciseRepository: dependencies.exerciseRepository,
                    workoutRepository: dependencies.workoutRepository,
                    templateRepository: dependencies.templateRepository,
                    preferenceRepository: dependencies.preferenceRepository,
                    chatRepository: dependencies.chatRepository,
                    // Without this, ChatViewModel.selectedModel silently falls
                    // back to Haiku regardless of what the user picked in
                    // Settings — the root cause of the "Settings says Opus
                    // but Coach shows Haiku" bug.
                    settings: dependencies.settings,
                    appState: appState,
                    autoFillService: dependencies.autoFillService,
                    prDetectionService: dependencies.prDetectionService,
                    baselineRepository: dependencies.baselineRepository
                )
            }
        }
        // Observe the *workout id* rather than just isWorkoutActive so we fire
        // once the async ActiveWorkoutViewModel.startWorkout() has finished
        // assigning a Workout. This replaces the old 500ms sleep workaround.
        .onChange(of: appState.activeWorkoutVM?.workout?.id) { _, _ in
            chatViewModel?.activeWorkout = appState.activeWorkoutVM?.workout
        }
        .onChange(of: appState.isWorkoutActive) { _, isActive in
            if !isActive {
                chatViewModel?.activeWorkout = nil
            }
        }
    }

    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }

    private var coachTab: some View {
        NavigationStack {
            if let chatViewModel {
                ChatView(viewModel: chatViewModel)
            } else {
                ProgressView()
            }
        }
    }
}
