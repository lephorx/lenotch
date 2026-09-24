import AppKit

/// Reads and controls Spotify or Apple Music directly over AppleScript, so the
/// notch follows that app even when something else owns system Now Playing.
/// macOS asks the user once for permission to control the app.
final class AppleScriptProvider: PlaybackProvider {
    enum Player {
        case spotify, music

        var bundleIdentifier: String {
            switch self {
            case .spotify: "com.spotify.client"
            case .music: "com.apple.Music"
            }
        }

        var scriptName: String {
            switch self {
            case .spotify: "Spotify"
            case .music: "Music"
            }
        }

        /// Returns {title, artist, album, duration (s), position (s), state, track id, artwork url,
        /// shuffle, repeat ("off"/"one"/"all"), favorited or "" if unsupported}.
        /// The `is running` check keeps AppleScript from launching the player.
        var stateScript: String {
            switch self {
            case .spotify:
                """
                if application "Spotify" is running then
                    tell application "Spotify"
                        if player state is stopped then return {}
                        set t to current track
                        set r to "off"
                        if repeating then set r to "all"
                        return {name of t, artist of t, album of t, (duration of t) / 1000, player position, player state as string, id of t, artwork url of t, shuffling, r, ""}
                    end tell
                end if
                return {}
                """
            case .music:
                """
                if application "Music" is running then
                    tell application "Music"
                        if player state is stopped then return {}
                        set t to current track
                        set fav to false
                        try
                            set fav to favorited of t
                        end try
                        return {name of t, artist of t, album of t, duration of t, player position, player state as string, persistent ID of t, "", shuffle enabled, song repeat as string, fav}
                    end tell
                end if
                return {}
                """
            }
        }

        /// Spotify's repeat is a plain on/off switch.
        var repeatModes: [RepeatMode] {
            switch self {
            case .spotify: [.off, .all]
            case .music: [.off, .all, .one]
            }
        }
    }

    var onUpdate: ((PlaybackSnapshot?) -> Void)?

    private let player: Player
    private let queue = DispatchQueue(label: "Lenotch.AppleScript")
    private var timer: DispatchSourceTimer?
    /// Compiled once: compiling runs a malware scan, which is too costly to repeat every second.
    private lazy var stateScript: NSAppleScript? = {
        let script = NSAppleScript(source: player.stateScript)
        var error: NSDictionary?
        script?.compileAndReturnError(&error)
        return script
    }()

    // Only touched on `queue`.
    private var lastTrackID: String?
    private var artwork: NSImage?

    init(player: Player) {
        self.player = player
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func togglePlayPause() { command("playpause") }
    func nextTrack() { command("next track") }
    func previousTrack() { command("previous track") }
    func seek(to seconds: Double) { command("set player position to \(String(format: "%.3f", seconds))") }

    var repeatModes: [RepeatMode] { player.repeatModes }

    func setShuffle(_ enabled: Bool) {
        switch player {
        case .spotify: command("set shuffling to \(enabled)")
        case .music: command("set shuffle enabled to \(enabled)")
        }
    }

    func setRepeat(_ mode: RepeatMode) {
        switch player {
        case .spotify:
            command("set repeating to \(mode != .off)")
        case .music:
            let value = switch mode {
            case .off: "off"
            case .one: "one"
            case .all: "all"
            }
            command("set song repeat to \(value)")
        }
    }

    /// Favoriting in Music also adds the song to the library (Music's default setting).
    /// Spotify's scripting interface can't change liked songs.
    func setFavorite(_ favorite: Bool) {
        guard player == .music else { return }
        command("set favorited of current track to \(favorite)")
    }

    // MARK: - Scripting

    private var isPlayerRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    /// Only talk to the player once the user has allowed it (Settings → Permissions);
    /// sending an Apple Event without permission would make macOS ask on its own.
    private var isAllowed: Bool { Self.isAllowed(player.bundleIdentifier) }

    static func isAllowed(_ bundleIdentifier: String) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let descriptor = target.aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(descriptor, typeWildCard, typeWildCard, false) == noErr
    }

    private func command(_ body: String) {
        queue.async { [self] in
            guard isPlayerRunning, isAllowed else { return }
            execute("tell application \"\(player.scriptName)\" to \(body)")
            poll()
        }
    }

    private func poll() {
        let snapshot = isPlayerRunning && isAllowed ? readState() : nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil else { return }
            self.onUpdate?(snapshot)
        }
    }

    private func readState() -> PlaybackSnapshot? {
        var error: NSDictionary?
        guard let result = stateScript?.executeAndReturnError(&error) else {
            if let error { NSLog("Lenotch: \(player.scriptName) script failed: \(error)") }
            return nil
        }
        guard result.numberOfItems >= 11,
              let title = result.atIndex(1)?.stringValue, !title.isEmpty else { return nil }

        let trackID = result.atIndex(7)?.stringValue
        if trackID != lastTrackID {
            lastTrackID = trackID
            artwork = loadArtwork(url: result.atIndex(8)?.stringValue)
        }

        let track = Track(title: title,
                          artist: result.atIndex(2)?.stringValue ?? "",
                          album: result.atIndex(3)?.stringValue ?? "",
                          duration: result.atIndex(4)?.doubleValue ?? 0,
                          bundleIdentifier: player.bundleIdentifier)
        return PlaybackSnapshot(track: track,
                                isPlaying: result.atIndex(6)?.stringValue == "playing",
                                elapsed: result.atIndex(5)?.doubleValue ?? 0,
                                timestamp: Date(),
                                rate: 1,
                                artwork: artwork,
                                shuffle: result.atIndex(9)?.booleanValue,
                                repeatMode: Self.repeatMode(result.atIndex(10)?.stringValue),
                                isFavorite: player == .music ? result.atIndex(11)?.booleanValue : nil)
    }

    private static func repeatMode(_ value: String?) -> RepeatMode? {
        switch value {
        case "off": .off
        case "one": .one
        case "all": .all
        default: nil
        }
    }

    private func loadArtwork(url: String?) -> NSImage? {
        switch player {
        case .spotify:
            guard let url = url.flatMap(URL.init(string:)), let data = try? Data(contentsOf: url) else { return nil }
            return ImageDownsampling.image(from: data)
        case .music:
            let data = execute("""
                tell application "Music"
                    try
                        return raw data of artwork 1 of current track
                    end try
                end tell
                """)?.data
            return data.flatMap { ImageDownsampling.image(from: $0) }
        }
    }

    @discardableResult
    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Lenotch: AppleScript failed: \(error)") }
        return result
    }
}
