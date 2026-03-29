import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            HistoryListView()
                .tabItem { Label("History", systemImage: "calendar") }

            ExerciseLibraryView()
                .tabItem { Label("Exercises", systemImage: "dumbbell") }

            NavigationStack {
                ChatView(viewModel: ChatViewModel(
                    anthropicService: AnthropicService(apiKey: SettingsManager().apiKey),
                    exerciseRepository: SwiftDataExerciseRepository(context: modelContext),
                    workoutRepository: SwiftDataWorkoutRepository(context: modelContext),
                    templateRepository: SwiftDataTemplateRepository(context: modelContext),
                    preferenceRepository: SwiftDataTrainingPreferenceRepository(context: modelContext)
                ))
            }
            .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .preferredColorScheme(.dark)
    }
}
