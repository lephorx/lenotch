import AppKit
import Observation

/// Playback state shown by the notch, fed by the provider for the selected source.
@Observable
final class NowPlayingService {
    private(set) var source: AudioSource
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage? {
        didSet {
            guard artwork !== oldValue else { return }
            accentColor = artwork.flatMap(ArtworkColor.accent)
        }
    }
    /// Vivid colour taken from the artwork, for tinting.
    private(set) var accentColor: NSColor?
    /// `nil` when the player doesn't report shuffle/repeat/favorite.
    private(set) var shuffle: Bool?
    private(set) var repeatMode: RepeatMode?
    private(set) var isFavorite: Bool?
    private(set) var appIcon: NSImage?
    private(set) var appName: String?

    private var elapsedAtTimestamp: Double = 0
    private var timestamp = Date()
    private var playbackRate: Double = 1

    @ObservationIgnored private var provider: PlaybackProvider?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var appIconBundleID: String?
    /// Play state set locally by a toggle, held until the player confirms it so
    /// updates already in flight don't flip the button back and forth.
    @ObservationIgnored private var pendingPlayState: (isPlaying: Bool, until: Date)?
    /// After a local seek, ignore reported positions until the player catches up.
    @ObservationIgnored private var clockHoldUntil: Date?
    /// After a local shuffle/repeat/favorite change, ignore reported values briefly.
    @ObservationIgnored private var extrasHoldUntil: Date?

    init(source: AudioSource) {
        self.source = source
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startProvider()
    }

    func stop() {
        isRunning = false
        provider?.stop()
        provider = nil
    }

    func setSource(_ source: AudioSource) {
        guard source != self.source else { return }
        self.source = source
        provider?.stop()
        provider = nil
        apply(nil)
        if isRunning { startProvider() }
    }

    private func startProvider() {
        let provider = Self.makeProvider(for: source)
        provider.onUpdate = { [weak self] in self?.apply($0) }
        provider.start()
        self.provider = provider
    }

    private static func makeProvider(for source: AudioSource) -> PlaybackProvider {
        switch source {
        case .nowPlaying:
            MediaRemoteProvider()
        case .spotify:
            AppleScriptProvider(player: .spotify)
        case .appleMusic:
            AppleScriptProvider(player: .music)
        case .youtubeMusic:
            MediaRemoteProvider { YouTubeMusic.matches(bundleIdentifier: $0.bundleIdentifier, album: $0.album) }
        }
    }

    // MARK: - Playback

    func elapsed(at date: Date = Date()) -> Double {
        guard let track else { return 0 }
        var value = elapsedAtTimestamp
        if isPlaying {
            value += date.timeIntervalSince(timestamp) * playbackRate
        }
        return track.duration > 0 ? min(max(value, 0), track.duration) : max(value, 0)
    }

    func togglePlayPause() {
        // Freeze the clock at the current position before flipping the state.
        elapsedAtTimestamp = elapsed()
        timestamp = Date()
        isPlaying.toggle()
        pendingPlayState = (isPlaying, Date().addingTimeInterval(1.5))
        provider?.togglePlayPause()
    }

    func toggleShuffle() {
        guard let shuffle else { return }
        self.shuffle = !shuffle
        extrasHoldUntil = Date().addingTimeInterval(1.5)
        provider?.setShuffle(!shuffle)
    }

    func cycleRepeat() {
        guard let repeatMode, let modes = provider?.repeatModes, !modes.isEmpty else { return }
        let index = modes.firstIndex(of: repeatMode) ?? -1
        let next = modes[(index + 1) % modes.count]
        self.repeatMode = next
        extrasHoldUntil = Date().addingTimeInterval(1.5)
        provider?.setRepeat(next)
    }

    func toggleFavorite() {
        guard let isFavorite else { return }
        self.isFavorite = !isFavorite
        extrasHoldUntil = Date().addingTimeInterval(1.5)
        provider?.setFavorite(!isFavorite)
    }

    func nextTrack() { provider?.nextTrack() }
    func previousTrack() { provider?.previousTrack() }

    func seek(to seconds: Double) {
        elapsedAtTimestamp = seconds
        timestamp = Date()
        clockHoldUntil = Date().addingTimeInterval(2)
        provider?.seek(to: seconds)
    }

    func openSourceApp() {
        guard let id = track?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func apply(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot else {
            track = nil
            isPlaying = false
            artwork = nil
            pendingPlayState = nil
            clockHoldUntil = nil
            shuffle = nil
            repeatMode = nil
            isFavorite = nil
            return
        }

        let trackChanged = track != snapshot.track
        if trackChanged { track = snapshot.track }
        if artwork !== snapshot.artwork { artwork = snapshot.artwork }
        updateAppInfo(bundleID: snapshot.track.bundleIdentifier)

        let now = Date()
        if let holdUntil = extrasHoldUntil, now < holdUntil, !trackChanged {
            // Keep the locally toggled values until the player has caught up.
        } else {
            extrasHoldUntil = nil
            if shuffle != snapshot.shuffle { shuffle = snapshot.shuffle }
            if repeatMode != snapshot.repeatMode { repeatMode = snapshot.repeatMode }
            if isFavorite != snapshot.isFavorite { isFavorite = snapshot.isFavorite }
        }

        if let pending = pendingPlayState {
            guard pending.isPlaying == snapshot.isPlaying || now > pending.until else {
                return  // Stale update from before the toggle.
            }
            pendingPlayState = nil
        }

        // How far the reported position is from the one we're already showing.
        var reported = snapshot.elapsed
        if snapshot.isPlaying { reported += now.timeIntervalSince(snapshot.timestamp) * snapshot.rate }
        let drift = abs(reported - elapsed(at: now))

        if let holdUntil = clockHoldUntil {
            guard drift < 1.5 || now > holdUntil || trackChanged else {
                return  // The player hasn't applied our seek yet.
            }
            clockHoldUntil = nil
        }

        let playStateChanged = isPlaying != snapshot.isPlaying
        if playStateChanged { isPlaying = snapshot.isPlaying }

        // Only resync the clock when it actually matters, so small timing noise
        // in each update doesn't make the progress bar twitch.
        if trackChanged || playStateChanged || drift > 0.75 || playbackRate != snapshot.rate {
            playbackRate = snapshot.rate
            elapsedAtTimestamp = snapshot.elapsed
            timestamp = snapshot.timestamp
        }
    }

    private func updateAppInfo(bundleID: String?) {
        guard bundleID != appIconBundleID else { return }
        appIconBundleID = bundleID
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            appIcon = NSWorkspace.shared.icon(forFile: url.path)
            appName = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        } else {
            appIcon = nil
            appName = nil
        }
    }
}
