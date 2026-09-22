import AppKit
import SwiftUI

enum MediaPlayer: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case music = "Music"

    var id: String { rawValue }
    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }
    var displayName: String { self == .spotify ? "Spotify" : "Apple Music" }
    var symbol: String { self == .spotify ? "music.note" : "music.note.list" }
}

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var isPlaying: Bool = false
    var position: Double = 0
    var duration: Double = 0
    var trackID: String = ""
    var shuffle: Bool = false
    var repeating: Bool = false

    var isEmpty: Bool { title.isEmpty && artist.isEmpty }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

@MainActor
final class MediaController: ObservableObject {
    @Published private(set) var nowPlaying = NowPlaying()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkColors: [Color] = Theme.artworkFallback
    @Published private(set) var isRunning = false
    @Published private(set) var needsAutomationPermission = false
    @Published var player: MediaPlayer = .spotify {
        didSet {
            guard oldValue != player else { return }
            Settings.shared.preferredPlayer = player.rawValue
            artwork = nil
            artworkColors = Theme.artworkFallback
            nowPlaying = NowPlaying()
            refresh()
        }
    }



    private let runner = AppleScriptRunner()
    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkKey = ""
    /// Position is interpolated locally between polls so the scrubber moves at 60fps
    /// instead of ticking once a second.
    private var lastPollDate = Date()

    init() {
        if let stored = MediaPlayer(rawValue: Settings.shared.preferredPlayer) {
            player = stored
        }
        start()
    }

    func start() {
        refresh()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Smoothly advances the playhead between polls. Called from the view's timeline.
    func interpolatedPosition(at date: Date) -> Double {
        guard nowPlaying.isPlaying, nowPlaying.duration > 0 else { return nowPlaying.position }
        let elapsed = date.timeIntervalSince(lastPollDate)
        return min(nowPlaying.position + elapsed, nowPlaying.duration)
    }

    // MARK: - Transport

    func playPause() { fire("playpause") ; nudge() }
    func next() { fire(player == .spotify ? "next track" : "next track") ; nudge() }
    func previous() { fire(player == .spotify ? "previous track" : "back track") ; nudge() }

    func seek(toFraction fraction: Double) {
        let seconds = fraction * nowPlaying.duration
        guard seconds.isFinite, seconds >= 0 else { return }
        nowPlaying.position = seconds
        lastPollDate = Date()
        fire("set player position to \(String(format: "%.2f", seconds))")
    }

    func toggleShuffle() {
        let new = !nowPlaying.shuffle
        nowPlaying.shuffle = new
        fire(player == .spotify ? "set shuffling to \(new)" : "set shuffle enabled to \(new)")
    }

    func toggleRepeat() {
        let new = !nowPlaying.repeating
        nowPlaying.repeating = new
        if player == .spotify {
            fire("set repeating to \(new)")
        } else {
            fire("set song repeat to \(new ? "all" : "off")")
        }
    }

    func launchPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealInPlayer() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func fire(_ command: String) {
        let script = "tell application \"\(player.rawValue)\" to \(command)"
        let runner = runner
        Task.detached(priority: .userInitiated) { _ = runner.run(script) }
    }

    /// Players need a beat to settle before they report the new state.
    private func nudge() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            refresh()
        }
    }

    // MARK: - Polling

    private func refresh() {
        let player = player
        let runner = runner
        let script = Self.stateScript(for: player)

        Task.detached(priority: .utility) { [weak self] in
            let result = runner.run(script)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .failure(.notPermitted):
                    self.needsAutomationPermission = true
                    self.isRunning = false
                case .failure:
                    self.isRunning = false
                    self.nowPlaying = NowPlaying()
                case .success(let box):
                    self.needsAutomationPermission = false
                    self.apply(raw: box.string)
                }
            }
        }
    }

    private func apply(raw: String) {
        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count >= 8 else {
            isRunning = false
            nowPlaying = NowPlaying()
            return
        }
        guard parts[0] == "1" else {
            isRunning = false
            nowPlaying = NowPlaying()
            artwork = nil
            return
        }

        isRunning = true
        var state = NowPlaying()
        state.isPlaying = parts[1] == "playing"
        state.title = parts[2]
        state.artist = parts[3]
        state.album = parts[4]
        state.duration = Double(parts[5]) ?? 0
        state.position = Double(parts[6]) ?? 0
        state.trackID = parts[7]
        if parts.count > 8 { state.shuffle = parts[8] == "true" }
        if parts.count > 9 { state.repeating = parts[9] != "false" && parts[9] != "off" }

        lastPollDate = Date()
        if state != nowPlaying { nowPlaying = state }

        let artURL = parts.count > 10 ? parts[10] : ""
        loadArtworkIfNeeded(trackID: state.trackID, urlString: artURL)
    }

    private func loadArtworkIfNeeded(trackID: String, urlString: String) {
        let key = trackID.isEmpty ? urlString : trackID
        guard !key.isEmpty, key != lastArtworkKey else { return }
        lastArtworkKey = key
        artworkTask?.cancel()

        if player == .spotify, let url = URL(string: urlString), !urlString.isEmpty {
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data), !Task.isCancelled else { return }
                await MainActor.run { [weak self] in self?.setArtwork(image) }
            }
        } else {
            let runner = runner
            artworkTask = Task.detached(priority: .utility) { [weak self] in
                let result = runner.run(MediaController.musicArtworkScript)
                guard case .success(let box) = result,
                      let data = box.data,
                      let image = NSImage(data: data) else { return }
                await MainActor.run { [weak self] in self?.setArtwork(image) }
            }
        }
    }

    private func setArtwork(_ image: NSImage) {
        artwork = image
        artworkColors = image.dominantColors()
    }

    // MARK: - Scripts

    nonisolated private static func stateScript(for player: MediaPlayer) -> String {
        let sep = "\u{1F}"
        if player == .spotify {
            return """
            set out to "0"
            if application "Spotify" is running then
              tell application "Spotify"
                try
                  set t to current track
                  set out to "1" & "\(sep)" & (player state as string) ¬
                    & "\(sep)" & (name of t) & "\(sep)" & (artist of t) ¬
                    & "\(sep)" & (album of t) & "\(sep)" & ((duration of t) / 1000) ¬
                    & "\(sep)" & (player position) & "\(sep)" & (id of t) ¬
                    & "\(sep)" & (shuffling as string) & "\(sep)" & (repeating as string) ¬
                    & "\(sep)" & (artwork url of t)
                on error
                  set out to "1" & "\(sep)" & (player state as string) & "\(sep)" & "" & "\(sep)" & "" ¬
                    & "\(sep)" & "" & "\(sep)" & "0" & "\(sep)" & "0" & "\(sep)" & "" ¬
                    & "\(sep)" & "false" & "\(sep)" & "false" & "\(sep)" & ""
                end try
              end tell
            end if
            return out
            """
        }
        return """
        set out to "0"
        if application "Music" is running then
          tell application "Music"
            try
              set t to current track
              set out to "1" & "\(sep)" & (player state as string) ¬
                & "\(sep)" & (name of t) & "\(sep)" & (artist of t) ¬
                & "\(sep)" & (album of t) & "\(sep)" & (duration of t) ¬
                & "\(sep)" & (player position) & "\(sep)" & (persistent ID of t) ¬
                & "\(sep)" & (shuffle enabled as string) & "\(sep)" & (song repeat as string) ¬
                & "\(sep)" & ""
            on error
              set out to "0"
            end try
          end tell
        end if
        return out
        """
    }

    nonisolated private static let musicArtworkScript = """
    tell application "Music"
      try
        return raw data of artwork 1 of current track
      on error
        return ""
      end try
    end tell
    """
}
