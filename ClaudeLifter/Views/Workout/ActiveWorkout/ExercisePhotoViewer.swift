import SwiftUI
import UIKit

/// The exercise whose photo is on screen (#170). A wrapper so
/// `.fullScreenCover(item:)` keys on the slot's stable id.
struct ExercisePhotoTarget: Identifiable {
    let id: UUID
    let name: String
    let source: ExercisePhotoSource
    let note: String?
}

/// The machine photo full screen, with the machine note over it and a
/// visible Close (UI-P4: swipe-to-dismiss is never the only way out).
struct ExercisePhotoViewer: View {
    let target: ExercisePhotoTarget

    @Environment(\.dismiss) private var dismiss
    @State private var userImage: UIImage?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                photo
            }
            .overlay(alignment: .bottom) {
                if let note = target.note {
                    noteOverlay(note)
                }
            }
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeExercisePhoto")
                }
            }
            .task {
                guard case .userPhoto(let path) = target.source else { return }
                userImage = await ExercisePhotoLoader.load(relativePath: path, maxPixel: nil)
                didLoad = true
            }
        }
    }

    @ViewBuilder
    private var photo: some View {
        switch target.source {
        case .userPhoto:
            if let userImage {
                Image(uiImage: userImage)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Photo of \(target.name)")
            } else if didLoad {
                unavailable
            } else {
                ProgressView("Loading photo…")
            }
        case .catalog(let url):
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .accessibilityLabel("Catalog picture of \(target.name)")
                case .failure:
                    unavailable
                default:
                    ProgressView("Loading photo…")
                }
            }
        }
    }

    private var unavailable: some View {
        ContentUnavailableView(
            "Photo unavailable",
            systemImage: "photo",
            description: Text("It will appear once it has downloaded.")
        )
    }

    private func noteOverlay(_ note: String) -> some View {
        Label(note, systemImage: "note.text")
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(16)
            .accessibilityLabel("Note: \(note)")
    }
}
