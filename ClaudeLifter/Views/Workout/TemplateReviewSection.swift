import SwiftUI

/// Post-workout template reconciliation, shown on the completion summary (#130).
///
/// Deliberately inline in the summary rather than a second sheet: presenting a
/// sheet from a sheet is where SwiftUI dismissal races live, and this screen is
/// already the one place where a stranded presentation cost the user a whole
/// workout once (#123). Expanding in place cannot strand anything.
///
/// It appears **only** when there is something to decide, and its default is to
/// do nothing — the workout is already saved, and the template is the user's.
struct TemplateReviewSection: View {
    let changeSet: TemplateChangeSet
    let onApply: ([TemplateChange]) async -> String?

    /// Where the user has got to. Explicit rather than a pile of booleans,
    /// because "declined" and "applied" must not be able to render as each
    /// other — telling someone their template was updated when it was not is
    /// worse than any of this being on screen at all.
    private enum Outcome {
        case undecided
        case reviewing
        case declined
        case applied
    }

    @State private var outcome: Outcome = .undecided
    @State private var selected: Set<String> = []
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch outcome {
            case .undecided: promptState
            case .reviewing: reviewState
            case .declined: closedState(text: "Template left unchanged")
            case .applied: closedState(text: "Template updated")
            }
        }
        .padding()
        .background(BrandTheme.accent.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            // Everything selected by default: the user came here because the
            // changes describe what they actually did.
            if selected.isEmpty {
                selected = Set(changeSet.changes.map(\.id))
            }
        }
    }

    private var promptState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Update \(changeSet.templateName)?", systemImage: "square.and.pencil")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button("Review changes") { outcome = .reviewing }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reviewTemplateChanges")
                Spacer()
                Button("Keep unchanged") { outcome = .declined }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update \(changeSet.templateName)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if changeSet.hasConflict {
                Label(
                    "This template changed somewhere else since you started. Applying may overwrite that.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            ForEach(changeSet.changes) { change in
                Toggle(isOn: binding(for: change)) {
                    Text(description(of: change))
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Not now") { outcome = .declined }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apply") { Task { await apply() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || isApplying)
                    .accessibilityIdentifier("applyTemplateChanges")
            }
        }
    }

    private func closedState(text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLine: String {
        let count = changeSet.changes.count
        let noun = count == 1 ? "change" : "changes"
        return "This workout differed from the template in \(count) \(noun)."
    }

    private func binding(for change: TemplateChange) -> Binding<Bool> {
        Binding(
            get: { selected.contains(change.id) },
            set: { isOn in
                if isOn { selected.insert(change.id) } else { selected.remove(change.id) }
            }
        )
    }

    private func apply() async {
        isApplying = true
        errorMessage = nil
        let chosen = changeSet.changes.filter { selected.contains($0.id) }
        let failure = await onApply(chosen)
        isApplying = false
        if let failure {
            // Stay in the review state so the user can retry or decline. The
            // workout is saved either way, which is what the message says.
            errorMessage = failure
        } else {
            outcome = .applied
        }
    }

    private func description(of change: TemplateChange) -> String {
        switch change {
        case .addedExercise(let c):
            let reps = c.reps.map { " × \($0)" } ?? ""
            return "Add \(c.name) (\(c.sets) sets\(reps))"
        case .removedExercise(let c):
            return "Remove \(c.name)"
        case .reordered(let c):
            return "Reorder to: \(c.names.joined(separator: ", "))"
        case .setCountChanged(let c):
            return "\(c.name): \(c.from) → \(c.to) sets"
        case .cueChanged(let c):
            return "\(c.name) note: “\(c.to ?? "")”"
        }
    }
}
