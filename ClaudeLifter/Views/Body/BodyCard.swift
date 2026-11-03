import SwiftUI

/// The Body tab's card (UI-S2, UI-P1): 12 pt continuous corners, 16 pt
/// padding, a `.headline` title and at most one trailing action.
struct BodyCard<Trailing: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            BrandTheme.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    /// Title and action side by side; stacked at accessibility sizes so the
    /// title never truncates (UI-A3).
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(BrandTheme.accent)
            }
            .accessibilityAddTraits(.isHeader)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            trailing
        }
    }
}

extension BodyCard where Trailing == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// An inline error with a way forward (UI-E1, UI-E3): never an alert.
struct BodyErrorBanner: View {
    let message: String
    var actionTitle = "Retry"
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(BrandTheme.warning)
            Button(actionTitle, action: action)
                .secondaryActionStyle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled spinner for a card that is still loading (UI-E1).
struct BodyLoadingRow: View {
    let label: String

    var body: some View {
        ProgressView(label)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// A full-width row that pushes or opens something: the whole row is the
/// target (UI-T1, UI-P5).
struct BodyDisclosureLabel: View {
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .font(.body)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

// MARK: - Quick-entry sheets (UI-P4)

private struct QuickEntryDetents: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric private var height: CGFloat

    init(height: CGFloat) {
        _height = ScaledMetric(wrappedValue: height, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        content.presentationDetents(
            dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(height)]
        )
    }
}

extension View {
    /// A fitted sheet that grows with Dynamic Type, and the full sheet at
    /// accessibility sizes so nothing clips (UI-P4, UI-A3).
    func quickEntryDetents(height: CGFloat) -> some View {
        modifier(QuickEntryDetents(height: height))
    }

    /// A secondary action: gray `.bordered` with primary-colour text. Only
    /// the screen's primary action gets the tinted fill (UI-P1).
    func secondaryActionStyle() -> some View {
        buttonStyle(.bordered).tint(Color.primary)
    }

}

extension View {
    /// Focuses a sheet's first field once the sheet has finished presenting.
    /// Focusing during the presentation brings up the keyboard without its
    /// Done bar on iOS 27; a tap on the field later does show it.
    func focusAfterPresentation(_ focus: @escaping @MainActor () -> Void) -> some View {
        task {
            // `try?` is deliberate: the sleep throws only when the sheet
            // closes first, and then there is nothing to focus.
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            focus()
        }
    }
}

/// The keyboard's Done button, which dismisses it (UI-P4). Put it in the
/// sheet's own `.toolbar` block, beside Cancel and Save: a keyboard item in a
/// second `.toolbar` modifier did not appear on iOS 27.
struct KeyboardDoneItem: ToolbarContent {
    let identifier: String
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done", action: action)
                .accessibilityIdentifier(identifier)
        }
    }
}
