import SwiftUI
import PhotosUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    @State private var photoVM = ExercisePhotoViewModel()
    @State private var selectedItem: PhotosPickerItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            errorBanner
            List {
                imageSection
                photoSection
                musclesSection
                if !exercise.instructions.isEmpty {
                    instructionsSection
                }
                metadataSection
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        // Use .task instead of .onAppear — .onAppear re-fires on every view
        // redraw (e.g. navigation push/pop, orientation change), which would
        // overwrite any local photo state the user has just chosen.
        .task {
            if photoVM.photoURL == nil {
                photoVM.photoURL = exercise.photoURL
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await handlePhotoSelection(newItem)
                selectedItem = nil
            }
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
            if let photoURL = photoVM.photoURL, !photoURL.isEmpty,
               let uiImage = LocalPhotoStorage.loadImage(relativePath: photoURL) {
                UserPhotoView(
                    image: Image(uiImage: uiImage),
                    onPhotoSelected: handlePhotoSelection
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
        .disabled(photoVM.isSaving)
    }

    // MARK: - Photo handling

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        await photoVM.attachPhoto(to: exercise) {
            try await item.loadTransferable(type: Data.self)
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let errorMessage = photoVM.errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    photoVM.errorMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss error")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .accessibilityIdentifier("exercisePhotoErrorBanner")
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
    let onPhotoSelected: (PhotosPickerItem) async -> Void

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
            Task {
                await onPhotoSelected(newItem)
                selectedItem = nil
            }
        }
    }
}
