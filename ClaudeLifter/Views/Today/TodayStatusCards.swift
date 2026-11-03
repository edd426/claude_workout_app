import SwiftUI

/// "Needs you": pending approvals and open reports in one row, shown only
/// when either is non-zero (UI-P2). With both, the row is a menu so each is
/// one more tap; with one, it opens that screen directly.
struct NeedsYouCard: View {
    let summary: NeedsYouSummary
    let onReviewChanges: () -> Void
    let onOpenReports: () -> Void

    var body: some View {
        if let approvals = summary.approvalsText, let reports = summary.reportsText {
            Menu {
                Button(approvals, systemImage: "checkmark.shield", action: onReviewChanges)
                Button(reports, systemImage: "flag", action: onOpenReports)
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("needsYouCard")
        } else {
            Button(action: summary.pendingApprovals > 0 ? onReviewChanges : onOpenReports) {
                row
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("needsYouCard")
        }
    }

    private var row: some View {
        TodayStatusRow(
            systemImage: "tray.full.fill",
            title: "Needs you",
            detail: summary.title
        )
    }
}

/// "This week" (#168): the muscles under 4 sets, two lines at most. Taps
/// through to the per-muscle detail.
struct WeeklyVolumeCard: View {
    let volume: WeeklyMuscleVolume

    var body: some View {
        NavigationLink {
            WeeklyVolumeDetailView(volume: volume)
        } label: {
            TodayStatusRow(
                systemImage: "chart.bar.fill",
                title: "This week",
                detail: volume.cardSummary(),
                iconStyle: volume.underMinimum.isEmpty ? BrandTheme.success : BrandTheme.accent
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weeklyVolumeCard")
    }
}

/// What the Body row shows. Built by `HomeView` from the body-weight
/// ViewModels, which it only reads.
struct TodayBodyLine: Equatable {
    let text: String
    let isStale: Bool
}

/// "Body": latest weight, its age and the pace against the goal, one row.
/// Opens the Body tab.
struct TodayBodyCard: View {
    let line: TodayBodyLine
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            TodayStatusRow(
                systemImage: line.isStale ? "exclamationmark.circle.fill" : "scalemass.fill",
                title: line.isStale ? "Body · weigh-in is stale" : "Body",
                detail: line.text,
                detailLineLimit: 2,
                iconStyle: line.isStale ? BrandTheme.warning : BrandTheme.accent
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Body tab")
        .accessibilityIdentifier("todayBodyCard")
    }
}

/// One insight, dismissable; the rest sit behind "More" (UI-P2).
struct TodayInsightSection: View {
    let insights: [ProactiveInsight]
    let onDismiss: @MainActor (ProactiveInsight) async -> Void

    @State private var showsAll = false

    private var visible: [ProactiveInsight] {
        showsAll ? insights : Array(insights.prefix(1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visible, id: \.id) { insight in
                InsightCardView(insight: insight) { await onDismiss(insight) }
            }
            if insights.count > 1 {
                Button {
                    showsAll.toggle()
                } label: {
                    Text(showsAll ? "Show fewer insights" : "More insights (\(insights.count - 1))")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandTheme.accentText)
                .accessibilityIdentifier("moreInsights")
            }
        }
    }
}
