import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    let exercise: Exercise
    var onSaveComplete: ((String) -> Void)?

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isSaving = false
    @State private var error: String? = nil
    @State private var displayImage: Image? = nil

    var body: some View {
        VStack(spacing: 16) {
            photoPreview
            saveControls
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task { await handleSelection(newItem) }
        }
        .onAppear { loadExistingPhoto() }
    }

    private var photoPreview: some View {
        Group {
            if let displayImage {
                displayImage
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(12)
            } else {
                placeholderImage
                    .frame(height: 200)
                    .cornerRadius(12)
            }
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    private var saveControls: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    exercise.photoURL != nil ? "Change Photo" : "Add Photo",
                    systemImage: "photo.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            if isSaving {
                ProgressView()
                    .frame(width: 44, height: 44)
            }
        }
    }

    private func loadExistingPhoto() {
        guard let uiImage = LocalPhotoStorage.loadImage(relativePath: exercise.photoURL) else { return }
        displayImage = Image(uiImage: uiImage)
    }

    private func handleSelection(_ item: PhotosPickerItem) async {
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = "Could not load the selected image."
            return
        }

        // Compress to JPEG before saving
        guard let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
            error = "Could not process the selected image."
            return
        }

        displayImage = Image(uiImage: uiImage)
        isSaving = true
        defer { isSaving = false }

        do {
            let relativePath = try LocalPhotoStorage.savePhoto(data: jpegData, exerciseId: exercise.id)
            onSaveComplete?(relativePath)
        } catch {
            self.error = "Could not save photo: \(error.localizedDescription)"
        }
    }
}
