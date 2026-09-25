import PhotosUI
import SwiftUI

/// File a complaint (issue #135). The gym version of this screen has to be
/// survivable one-handed between sets: pick a chip, type a sentence, Send.
/// Nothing else is required, and no context is asked for — it is all captured.
struct ReportSheetView: View {
    @State var vm: ReportSheetViewModel
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @FocusState private var detailFocused: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    categoryPicker
                } header: {
                    Text("What's wrong?")
                }

                Section {
                    TextField(
                        "Describe it in your own words",
                        text: $vm.detail,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .focused($detailFocused)
                    .accessibilityIdentifier("reportDetailField")

                    if vm.showsReplacementField {
                        TextField(
                            "What should it be instead? (optional)",
                            text: $vm.suggestedReplacement
                        )
                        .accessibilityIdentifier("reportReplacementField")
                    }
                }

                Section {
                    photoRow
                } header: {
                    Text("Photo")
                } footer: {
                    Text(
                        "Optional. Kept on your phone and uploaded on the next sync, "
                        + "so sending never waits for it."
                    )
                }

                if let contextSummary = vm.context.contextSummary {
                    Section {
                        Text(contextSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Attached automatically")
                    } footer: {
                        Text(
                            "Sent with the report so it can be looked into later. "
                            + "You don't need to write any of this down."
                        )
                    }
                }

                if let errorMessage = vm.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top, spacing: 0) {
                subjectBanner
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task {
                            if await vm.submit() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("submitReport")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        detailFocused = false
                    }
                    .accessibilityIdentifier("reportKeyboardDone")
                }
            }
            .task { detailFocused = true }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        vm.attachPhoto(data)
                    } else {
                        vm.photoError = "Couldn't load that photo. Try another one."
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { data in
                    vm.attachPhoto(data)
                }
                .ignoresSafeArea()
            }
        }
    }

    /// Issue #141: "It's easier to show you what's wrong as an image." The
    /// camera comes first because the machine is right there; the library is
    /// for a photo taken earlier.
    @ViewBuilder
    private var photoRow: some View {
        if let data = vm.photoData, let image = UIImage(data: data) {
            HStack(spacing: 12) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Attached photo")
                    .accessibilityIdentifier("reportPhotoThumbnail")
                Spacer()
                Button("Remove", role: .destructive) {
                    vm.removePhoto()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("reportRemovePhoto")
            }
        } else {
            // Explicit button styles: in a Form row, default-styled buttons
            // make the whole row one tap target that fires every button in it.
            HStack(spacing: 12) {
                if CameraPicker.isAvailable {
                    Button {
                        detailFocused = false
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reportTakePhoto")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reportChoosePhoto")
            }
        }
        if let photoError = vm.photoError {
            Text(photoError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var subjectBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag")
                .foregroundStyle(.secondary)
            Text(vm.context.subject)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var categoryPicker: some View {
        // A wrapping row of chips rather than a Picker: every option stays
        // visible and one-tap, which matters far more than saving a row.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(ReportCategory.allCases, id: \.self) { category in
                categoryChip(category)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryChip(_ category: ReportCategory) -> some View {
        let isSelected = vm.category == category
        return Button {
            vm.category = category
        } label: {
            Label(category.displayName, systemImage: category.systemImage)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 34)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected
                              ? BrandTheme.terracotta.opacity(0.2)
                              : Color(uiColor: .tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? BrandTheme.terracotta : .clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? BrandTheme.terracotta : .primary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("reportCategory_\(category.rawValue)")
    }
}
