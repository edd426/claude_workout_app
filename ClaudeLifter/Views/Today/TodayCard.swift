import SwiftUI

/// The one card container on Today (UI-P1, UI-S2): 12 pt continuous corners,
/// 16 pt inside, a solid semantic background (no glass in the content layer,
/// UI-P9).
struct TodayCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                BrandTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }
}

/// A status card that is one tappable row: an icon, a title, one or two
/// lines of detail and a chevron. The whole card is the target (UI-P5).
struct TodayStatusRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var detailLineLimit = 2
    var iconStyle: Color = BrandTheme.accent
    var showsChevron = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        TodayCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(iconStyle)
                    .frame(minWidth: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        // Two lines at default sizes; never clipped at the
                        // accessibility sizes (UI-A3).
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : detailLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
