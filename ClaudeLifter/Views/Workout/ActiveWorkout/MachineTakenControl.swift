import SwiftUI

/// "Machine taken" in a card header (#169): one tap opens the template's
/// alternatives, a second swaps in place. Undo is in the same menu, so there
/// is no confirmation. With no alternatives listed, the button goes straight
/// to Other… (the library).
///
/// UI-T2: gym-critical, so at least 56 × 56 pt. UI-A1: icon-only with a
/// label. UI-P7: a visible control, never swipe-only.
struct MachineTakenControl: View {
    let options: [AlternativeOption]
    /// The planned exercise's name when this slot is swapped, for Undo.
    let swappedFrom: String?
    let onSwap: (Exercise) -> Void
    let onUndo: () -> Void
    let onOther: () -> Void

    var body: some View {
        if options.isEmpty && swappedFrom == nil {
            Button(action: onOther) { icon }
                .buttonStyle(.plain)
                .accessibilityLabel("Machine taken")
                .accessibilityHint("Pick another exercise for this slot, today only")
                .accessibilityIdentifier("machineTaken")
        } else {
            Menu {
                menuContent
            } label: {
                icon
            }
            .accessibilityLabel("Machine taken")
            .accessibilityHint("Swap to an alternative, today only")
            .accessibilityIdentifier("machineTaken")
        }
    }

    private var icon: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.title3)
            .foregroundStyle(BrandTheme.accent)
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var menuContent: some View {
        if !options.isEmpty {
            Section("Machine taken? Swap for today") {
                ForEach(options) { option in
                    Button {
                        onSwap(option.exercise)
                    } label: {
                        Text(option.name)
                        if let detail = detail(for: option) {
                            Text(detail)
                        }
                    }
                    .accessibilityIdentifier("alternative_\(option.name)")
                }
            }
        }
        Section {
            Button {
                onOther()
            } label: {
                Label("Other…", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("machineTakenOther")
            if let swappedFrom {
                Button {
                    onUndo()
                } label: {
                    Label("Undo: back to \(swappedFrom)", systemImage: "arrow.uturn.backward")
                }
                .accessibilityIdentifier("undoSwap")
            }
        }
    }

    /// "last: 40 kg × 12 · if the rack is taken".
    private func detail(for option: AlternativeOption) -> String? {
        let parts = [option.lastText(), option.note].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
