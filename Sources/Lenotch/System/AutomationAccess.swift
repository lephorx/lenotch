import Foundation
import Observation

/// Whether Lenotch may send Apple Events to an app (Spotify, Music). macOS's check can
/// hang for minutes (seen with Spotify), so it never runs on the caller's thread:
/// callers read the last answer and a fresh check runs in the background.
@Observable
final class AutomationAccess {
    static let shared = AutomationAccess()

    /// Last answers by bundle identifier, for views (updated on the main thread).
    private(set) var results: [String: OSStatus] = [:]

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var latest: [String: OSStatus] = [:]
    @ObservationIgnored private var checking: Set<String> = []

    /// The last answer, from any thread; nil until the first check has finished.
    func result(for bundleID: String) -> OSStatus? {
        lock.withLock { latest[bundleID] }
    }

    func isAllowed(_ bundleID: String) -> Bool {
        result(for: bundleID) == noErr
    }

    /// Checks again in the background, unless a check for this app is still waiting on macOS.
    /// `ask` shows macOS's prompt, so only pass it from a user's click; those always run.
    func check(_ bundleID: String, ask: Bool = false, completion: ((OSStatus) -> Void)? = nil) {
        if !ask {
            guard lock.withLock({ checking.insert(bundleID).inserted }) else { return }
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            // `aeDesc` is only valid while `target` is alive.
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status = target.aeDesc.map {
                AEDeterminePermissionToAutomateTarget($0, typeWildCard, typeWildCard, ask)
            } ?? OSStatus(procNotFound)
            lock.withLock {
                latest[bundleID] = status
                if !ask { checking.remove(bundleID) }
            }
            DispatchQueue.main.async { [self] in
                results[bundleID] = status
                completion?(status)
            }
        }
    }
}
