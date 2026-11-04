import SwiftUI

/// Compact, state-free presentation for the screen-owned rest session.
///
/// ui-standards: the time is `.title2` (UI-G7, glanceable at arm's length)
/// and −15 / +15 / Skip are gym-critical, so each is at least 56 × 56 pt
/// (UI-T2), at the regular control size (`.small` is banned during a
/// workout, UI-T1).
struct RestTimerBarView: View {
    let remainingSeconds: Int
    let progress: Double
    let onSubtractTime: () -> Void
    let onAddTime: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            progressIndicator
            Text(formattedRestTime(remainingSeconds))
                .font(.title2.monospacedDigit().bold())
                .frame(minWidth: 64, alignment: .leading)
                .accessibilityLabel("Rest time remaining")
                .accessibilityValue(formattedRestTime(remainingSeconds))
            Spacer(minLength: 0)
            timerButton("−15s", label: "Minus 15 seconds", action: onSubtractTime)
            timerButton("+15s", label: "Plus 15 seconds", action: onAddTime)
            timerButton("Skip", label: "Skip rest", action: onSkip)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(BrandTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Progress may animate (UI-H3), unless motion is reduced.
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func timerButton(
        _ title: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.monospacedDigit())
                .frame(minWidth: 56, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(.gray)
        .accessibilityLabel(label)
    }
}

func formattedRestTime(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}
