import Foundation
import Combine

protocol RestTimerServiceProtocol: AnyObject {
    var tickPublisher: AnyPublisher<Void, Never> { get }
    func start()
    func stop()
}

final class RestTimerService: RestTimerServiceProtocol {
    private var timer: AnyCancellable?
    private let subject = PassthroughSubject<Void, Never>()

    var tickPublisher: AnyPublisher<Void, Never> {
        subject.eraseToAnyPublisher()
    }

    func start() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.subject.send()
            }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
