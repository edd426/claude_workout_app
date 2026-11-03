import SwiftUI

/// The first thing on Today: today's workout and one full-width Start
/// (1.9.0, UI-P2). Start is the screen's only tinted button (UI-P1) and is at
/// least 56 pt tall (UI-T2), so starting the planned workout is one tap.
/// Tapping the rest of the card opens the template preview.
struct TodayHeroCard: View {
    let template: WorkoutTemplate
    /// True when the template is named for today; false for the fallback.
    let isScheduledToday: Bool
    let subtitle: String
    let onStart: () -> Void

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                previewLink
                startButton
            }
        }
        .accessibilityIdentifier("todayHeroCard")
    }

    private var previewLink: some View {
        NavigationLink {
            TemplatePreviewView(template: template, onStartWorkout: onStart)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isScheduledToday ? "Today's workout" : "Up next")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BrandTheme.accentText)
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the exercises")
        .accessibilityIdentifier("template.\(template.name)")
    }

    private var startButton: some View {
        Button(action: onStart) {
            Label("Start", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .accessibilityLabel("Start \(template.name)")
        .accessibilityIdentifier("todayStartWorkout")
    }
}
