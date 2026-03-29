import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Home")
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            Text("History")
                .tabItem {
                    Label("History", systemImage: "calendar")
                }

            Text("Exercises")
                .tabItem {
                    Label("Exercises", systemImage: "dumbbell")
                }

            Text("Coach")
                .tabItem {
                    Label("Coach", systemImage: "bubble.left.and.bubble.right")
                }
        }
        .preferredColorScheme(.dark)
    }
}
