import SwiftUI

/// Root of the Body tab (1.9.0): weight, protein, measurements, medications.
/// Placeholder so the tab can be wired before the screen is built.
struct BodyView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Body", systemImage: "figure")
                .navigationTitle("Body")
        }
    }
}
