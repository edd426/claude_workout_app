import SwiftUI

/// Compact, state-free presentation for the screen-owned rest session.
struct RestTimerBarView: View {
    let remainingSeconds: Int
    let progress: Double
    let onSubtractTime: () -> Void
    let onAddTime: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            progressIndicator
            Text(formattedRestTime(remainingSeconds))
                .font(.headline.monospacedDigit())
                .frame(minWidth: 52)
                .accessibilityLabel("Rest time remaining")
                .accessibilityValue(formattedRestTime(remainingSeconds))
            timerButton("-15s", action: onSubtractTime)
            timerButton("+15s", action: onAddTime)
            timerButton("Skip", action: onSkip)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    BrandTheme.terracotta,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    private func timerButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minWidth: 44, minHeight: 44)
    }
}

func formattedRestTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
