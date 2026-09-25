import Foundation
import Observation

/// A countdown started from the notch. It keeps running while the notch is closed
/// and calls `onFinish` when it reaches zero.
@Observable
final class NotchTimer {
    /// The length it was started with (plus added minutes).
    private(set) var duration: TimeInterval = 0
    /// When it reaches zero while running.
    private(set) var endDate: Date?
    /// Time left while paused.
    private(set) var pausedRemaining: TimeInterval?

    /// Length of the timer that last finished, for the done card.
    @ObservationIgnored private(set) var lastDuration: TimeInterval = 0
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var finishTimer: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(endDate.timeIntervalSince(date), 0)
    }

    /// 1 when just started, 0 when done.
    func fraction(at date: Date = .now) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    func start(_ seconds: TimeInterval) {
        duration = seconds
        pausedRemaining = nil
        schedule(end: Date().addingTimeInterval(seconds))
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(endDate.timeIntervalSinceNow, 0)
        self.endDate = nil
        finishTimer?.invalidate()
    }

    func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        schedule(end: Date().addingTimeInterval(pausedRemaining))
    }

    func add(_ seconds: TimeInterval) {
        duration += seconds
        if let pausedRemaining {
            self.pausedRemaining = pausedRemaining + seconds
        } else if let endDate {
            schedule(end: endDate.addingTimeInterval(seconds))
        }
    }

    func cancel() {
        finishTimer?.invalidate()
        endDate = nil
        pausedRemaining = nil
        duration = 0
    }

    private func schedule(end: Date) {
        endDate = end
        finishTimer?.invalidate()
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.lastDuration = self.duration
            self.cancel()
            self.onFinish?()
        }
        RunLoop.main.add(timer, forMode: .common)
        finishTimer = timer
    }

    /// "4:59", "1:02:03".
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
