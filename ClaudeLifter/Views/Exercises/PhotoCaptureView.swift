import SwiftUI
import PhotosUI

struct PhotoCaptureView: View {
    let exercise: Exercise
    let uploadService: any ImageUploadServiceProtocol
    var onUploadComplete: ((String) -> Void)?

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isUploading = false
    @State private var error: String? = nil
    @State private var displayImage: Image? = nil

    var body: some View {
        VStack(spacing: 16) {
            photoPreview
            uploadControls
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
            } else if let photoURL = exercise.photoURL, !photoURL.isEmpty {
                AsyncImage(url: URL(string: photoURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholderImage
                    default:
                        ProgressView()
                    }
                }
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

    private var uploadControls: some View {
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
            .disabled(isUploading)

            if isUploading {
                ProgressView()
                    .frame(width: 44, height: 44)
            }
        }
    }

    private func handleSelection(_ item: PhotosPickerItem) async {
        error = nil
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = "Could not load the selected image."
            return
        }

        if let uiImage = UIImage(data: data) {
            displayImage = Image(uiImage: uiImage)
        }

        isUploading = true
        defer { isUploading = false }

        do {
            let url = try await uploadService.uploadPhoto(exerciseId: exercise.id, imageData: data)
            onUploadComplete?(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
