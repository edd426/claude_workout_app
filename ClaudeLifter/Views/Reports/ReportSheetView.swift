import SwiftUI

/// File a complaint (issue #135). The gym version of this screen has to be
/// survivable one-handed between sets: pick a chip, type a sentence, Send.
/// Nothing else is required, and no context is asked for — it is all captured.
struct ReportSheetView: View {
    @State var vm: ReportSheetViewModel
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @FocusState private var detailFocused: Bool

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
            }
            .task { detailFocused = true }
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
