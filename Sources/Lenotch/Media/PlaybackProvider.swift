import AppKit

struct Track: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var bundleIdentifier: String?
}

enum RepeatMode: Equatable {
    case off, one, all
}

/// A point-in-time view of the player. Elapsed time advances from `timestamp`
/// at `rate` while playing. Optional extras are `nil` when the player doesn't report them.
struct PlaybackSnapshot {
    var track: Track
    var isPlaying: Bool
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var artwork: NSImage?
    var shuffle: Bool?
    var repeatMode: RepeatMode?
    var isFavorite: Bool?
}

/// A backend that reports playback and forwards controls to a player.
/// `onUpdate` is called on the main thread; `nil` means nothing is playing.
protocol PlaybackProvider: AnyObject {
    var onUpdate: ((PlaybackSnapshot?) -> Void)? { get set }
    /// Repeat modes the player accepts, in cycling order.
    var repeatModes: [RepeatMode] { get }
    func start()
    func stop()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func seek(to seconds: Double)
    func setShuffle(_ enabled: Bool)
    func setRepeat(_ mode: RepeatMode)
    func setFavorite(_ favorite: Bool)
}

extension PlaybackProvider {
    var repeatModes: [RepeatMode] { [.off, .all, .one] }
    func setFavorite(_ favorite: Bool) {}
}
