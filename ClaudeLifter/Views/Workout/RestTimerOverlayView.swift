import SwiftUI
import Combine

struct RestTimerOverlayView: View {
    @State private var vm: RestTimerViewModel
    private var timerService: RestTimerService
    @State private var cancellable: AnyCancellable?
    let onDismiss: () -> Void

    init(durationSeconds: Int, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: RestTimerViewModel(durationSeconds: durationSeconds))
        timerService = RestTimerService()
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Rest Timer")
                .font(.headline)
                .foregroundStyle(.secondary)

            countdownDisplay

            adjustButtons

            skipButton
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(radius: 10)
        .onAppear {
            vm.start()
            timerService.start()
            cancellable = timerService.tickPublisher.sink { vm.tick() }
        }
        .onDisappear { timerService.stop() }
        .onChange(of: vm.isExpired) { _, expired in
            if expired { onDismiss() }
        }
    }

    private var countdownDisplay: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                .frame(width: 120, height: 120)
            Circle()
                .trim(from: 0, to: vm.progress)
                .stroke(BrandTheme.terracotta, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: vm.progress)
            Text(timeString(vm.remainingSeconds))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var adjustButtons: some View {
        HStack(spacing: 24) {
            Button("-15s") { vm.subtractTime(15) }
                .buttonStyle(.bordered)
            Button("+15s") { vm.addTime(15) }
                .buttonStyle(.bordered)
        }
    }

    private var skipButton: some View {
        Button("Skip") {
            vm.skip()
            onDismiss()
        }
        .foregroundStyle(.secondary)
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
