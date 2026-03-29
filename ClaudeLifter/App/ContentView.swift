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

            Text("Coach")
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .preferredColorScheme(.dark)
    }
}
