import SwiftUI
import PhotosUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    @State private var photoURL: String?
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isSaving = false

    var body: some View {
        List {
            imageSection
            photoSection
            musclesSection
            if !exercise.instructions.isEmpty {
                instructionsSection
            }
            metadataSection
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { photoURL = exercise.photoURL }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePhotoSelection(newItem) }
        }
    }

    // MARK: - Bundled exercise images

    @ViewBuilder
    private var imageSection: some View {
        let urls = bundledImageURLs
        if !urls.isEmpty {
            Section {
                BundledExerciseImagesView(urls: urls)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private var bundledImageURLs: [URL] {
        guard let imageURLString = exercise.imageURL,
              let firstURL = URL(string: imageURLString) else {
            return []
        }
        var urls: [URL] = [firstURL]
        if imageURLString.hasSuffix("/0.jpg") {
            let secondURLString = imageURLString.dropLast(5) + "1.jpg"
            if let secondURL = URL(string: String(secondURLString)) {
                urls.append(secondURL)
            }
        }
        return urls
    }

    // MARK: - User photo section

    @ViewBuilder
    private var photoSection: some View {
        Section {
            if let photoURL, !photoURL.isEmpty,
               let uiImage = LocalPhotoStorage.loadImage(relativePath: photoURL) {
                UserPhotoView(
                    image: Image(uiImage: uiImage),
                    exercise: exercise,
                    onPhotoUpdated: { self.photoURL = $0; exercise.photoURL = $0 }
                )
                .listRowInsets(EdgeInsets())
            } else {
                addPhotoButton
            }
        }
    }

    private var addPhotoButton: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack {
                Image(systemName: "camera")
                Text("Add Photo")
            }
            .foregroundStyle(BrandTheme.accent)
        }
        .disabled(isSaving)
    }

    // MARK: - Photo handling

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        isSaving = true
        defer { isSaving = false }
        if let path = try? LocalPhotoStorage.savePhoto(data: jpegData, exerciseId: exercise.id) {
            photoURL = path
            exercise.photoURL = path
        }
    }

    // MARK: - Muscles / instructions / metadata

    private var musclesSection: some View {
        Section("Muscles") {
            if !exercise.primaryMuscles.isEmpty {
                LabeledContent("Primary", value: exercise.primaryMuscles.joined(separator: ", "))
            }
            if !exercise.secondaryMuscles.isEmpty {
                LabeledContent("Secondary", value: exercise.secondaryMuscles.joined(separator: ", "))
            }
        }
    }

    private var instructionsSection: some View {
        Section("Instructions") {
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1).")
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(step)
                }
                .font(.body)
            }
        }
    }

    private var metadataSection: some View {
        Section("Details") {
            if let equipment = exercise.equipment {
                LabeledContent("Equipment", value: equipment)
            }
            if let level = exercise.level {
                LabeledContent("Level", value: level)
            }
            if let mechanic = exercise.mechanic {
                LabeledContent("Mechanic", value: mechanic)
            }
            if let force = exercise.force {
                LabeledContent("Force", value: force)
            }
        }
    }
}

// MARK: - Subviews

private struct BundledExerciseImagesView: View {
    let urls: [URL]

    var body: some View {
        if urls.count == 1 {
            exerciseImage(url: urls[0])
        } else {
            HStack(spacing: 2) {
                ForEach(urls, id: \.absoluteString) { url in
                    exerciseImage(url: url)
                }
            }
        }
    }

    private func exerciseImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            case .failure:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            default:
                Color.secondary.opacity(0.1)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .overlay { ProgressView() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UserPhotoView: View {
    let image: Image
    let exercise: Exercise
    let onPhotoUpdated: (String) -> Void

    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 8) {
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Change Photo", systemImage: "photo.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await handleSelection(newItem) }
        }
    }

    private func handleSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else { return }
        if let path = try? LocalPhotoStorage.savePhoto(data: jpegData, exerciseId: exercise.id) {
            onPhotoUpdated(path)
        }
    }
}
