import SwiftUI
import UIKit
import ImageIO

/// Where an exercise's picture comes from (#170): his own photo of the
/// machine first, else the catalog's start-position image, else nothing.
enum ExercisePhotoSource: Equatable {
    /// A local or downloaded photo, relative to Documents (`LocalPhotoStorage`).
    case userPhoto(String)
    /// The catalog's first image (a remote URL).
    case catalog(URL)

    @MainActor
    init?(exercise: Exercise) {
        if let path = exercise.photoURL, !path.isEmpty {
            self = .userPhoto(path)
        } else if let string = exercise.imageURL, let url = URL(string: string) {
            self = .catalog(url)
        } else {
            return nil
        }
    }
}

/// Loads a user photo off the main thread, so a card coming into view never
/// blocks on file I/O (UI-E5).
enum ExercisePhotoLoader {
    /// A decoded image handed from the background decode to the main actor.
    /// `CGImage` is immutable, so sharing it is safe.
    private struct Decoded: @unchecked Sendable {
        let image: CGImage
    }

    /// Reads and decodes the photo off the main thread, downsampled to
    /// `maxPixel` on its long side when given (ImageIO thumbnailing).
    @MainActor
    static func load(relativePath: String, maxPixel: CGFloat?) async -> UIImage? {
        let decoded = await Task.detached(priority: .userInitiated) { () -> Decoded? in
            guard
                let url = LocalPhotoStorage.resolveURL(relativePath: relativePath),
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            else { return nil }
            var options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let maxPixel {
                options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
            }
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }
            return Decoded(image: image)
        }.value
        return decoded.map { UIImage(cgImage: $0.image) }
    }
}

/// The 48 pt photo leading a card header. A button: tapping it shows the
/// photo full screen with the machine note.
struct ExerciseThumbnail: View {
    let exercise: Exercise
    /// Bumped by the ViewModel when background downloads land.
    let generation: Int
    let onShow: () -> Void

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 48
    @State private var userImage: UIImage?

    private var source: ExercisePhotoSource? { ExercisePhotoSource(exercise: exercise) }
    private var clampedSide: CGFloat { min(max(side, 44), 56) }

    var body: some View {
        if let source {
            Button(action: onShow) {
                image(for: source)
                    .frame(width: clampedSide, height: clampedSide)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo of \(exercise.name)")
            .accessibilityHint("Shows the photo full screen")
            .accessibilityIdentifier("exercisePhoto")
            .task(id: "\(exercise.photoURL ?? "")#\(generation)") {
                guard case .userPhoto(let path) = source else { return }
                userImage = await ExercisePhotoLoader.load(
                    relativePath: path,
                    maxPixel: clampedSide * displayScale
                )
            }
        }
    }

    @ViewBuilder
    private func image(for source: ExercisePhotoSource) -> some View {
        switch source {
        case .userPhoto:
            if let userImage {
                Image(uiImage: userImage).resizable().scaledToFill()
            } else {
                placeholder
            }
        case .catalog(let url):
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        }
    }

    /// Keeps the header still while loading or offline (UI-H3).
    private var placeholder: some View {
        Rectangle()
            .fill(Color(uiColor: .tertiarySystemFill))
            .overlay {
                Image(systemName: "photo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
    }
}
