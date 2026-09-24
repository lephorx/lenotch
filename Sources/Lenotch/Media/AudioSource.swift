import AppKit

/// Where the notch takes its playback info from.
enum AudioSource: String, CaseIterable, Identifiable {
    case nowPlaying
    case spotify
    case appleMusic
    case youtubeMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nowPlaying: "Playing Right Now"
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        case .youtubeMusic: "YouTube Music"
        }
    }

    var subtitle: String {
        switch self {
        case .nowPlaying: "Whatever app is playing"
        case .spotify: "Only the Spotify app"
        case .appleMusic: "Only the Music app"
        case .youtubeMusic: "Desktop app or browser tab"
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "waveform"
        case .spotify: "music.note"
        case .appleMusic: "music.note"
        case .youtubeMusic: "play.circle.fill"
        }
    }

    /// Bundle IDs of the native app(s) for this source.
    var bundleIdentifiers: [String] {
        switch self {
        case .nowPlaying: []
        case .spotify: ["com.spotify.client"]
        case .appleMusic: ["com.apple.Music"]
        case .youtubeMusic: YouTubeMusic.appBundleIdentifiers
        }
    }

    /// Icon of the installed app, if any.
    var appIcon: NSImage? {
        for id in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return ImageDownsampling.icon(forFile: url.path, points: 36)
            }
        }
        return nil
    }
}

enum YouTubeMusic {
    static let appBundleIdentifiers = [
        "com.github.th-ch.youtube-music",
        "com.github.th-ch.pear-desktop",
        "com.youtube.music",
    ]

    private static let browserBundleIdentifiers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi", "app.zen-browser.zen",
    ]

    /// Whether a Now Playing session likely comes from YouTube Music.
    ///
    /// Native wrappers are matched by bundle ID or name. Browsers don't report the
    /// page URL, so a browser session counts when it has an album, which YouTube
    /// Music sets and regular YouTube videos don't.
    static func matches(bundleIdentifier: String?, album: String) -> Bool {
        guard let id = bundleIdentifier else { return false }
        if appBundleIdentifiers.contains(id) { return true }
        if browserBundleIdentifiers.contains(id) { return !album.isEmpty }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url.lastPathComponent.localizedCaseInsensitiveContains("YouTube Music")
        }
        return false
    }
}
