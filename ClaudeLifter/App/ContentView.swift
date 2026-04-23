import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    let dependencies: DependencyContainer

    @State private var chatViewModel: ChatViewModel?

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            HistoryListView()
                .tabItem { Label("History", systemImage: "calendar") }

            ExerciseLibraryView()
                .tabItem { Label("Exercises", systemImage: "dumbbell") }

            NavigationStack {
                if let chatViewModel {
                    ChatView(viewModel: chatViewModel)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(BrandTheme.accent)
        .preferredColorScheme(.light)
        .task {
            if chatViewModel == nil {
                chatViewModel = ChatViewModel(
                    anthropicService: dependencies.anthropicService,
                    exerciseRepository: dependencies.exerciseRepository,
                    workoutRepository: dependencies.workoutRepository,
                    templateRepository: dependencies.templateRepository,
                    preferenceRepository: dependencies.preferenceRepository,
                    chatRepository: dependencies.chatRepository,
                    appState: appState,
                    autoFillService: dependencies.autoFillService
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
}
