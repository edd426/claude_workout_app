import SwiftUI

/// "Other workouts": every template that isn't the hero, as compact rows,
/// with Manage in the header, then an empty workout and a new template at
/// the end, so template creation stays one tap away.
struct OtherWorkoutsSection: View {
    let templates: [WorkoutTemplate]
    let lastDone: (WorkoutTemplate) -> Date?
    let onStart: (WorkoutTemplate) -> Void
    let onStartEmpty: () -> Void
    let onNewTemplate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            TodayCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(templates, id: \.id) { template in
                        templateLink(template)
                        Divider()
                    }
                    actionRow("Empty workout", systemImage: "play.circle", action: onStartEmpty)
                        .accessibilityLabel("Start Empty Workout")
                        .accessibilityIdentifier("startEmptyWorkout")
                    Divider()
                    actionRow("New template", systemImage: "plus.circle", action: onNewTemplate)
                        .accessibilityLabel("New Template")
                        .accessibilityIdentifier("newTemplateFromToday")
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Other workouts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            NavigationLink {
                TemplateListView()
            } label: {
                Text("Manage")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrandTheme.accentText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Manage Templates")
            .accessibilityIdentifier("manageTemplates")
        }
    }

    private func templateLink(_ template: WorkoutTemplate) -> some View {
        NavigationLink {
            TemplatePreviewView(template: template) { onStart(template) }
        } label: {
            HStack(spacing: 8) {
                TemplateRowView(template: template, lastDone: lastDone(template))
                chevron
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("template.\(template.name)")
    }

    private func actionRow(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(BrandTheme.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
