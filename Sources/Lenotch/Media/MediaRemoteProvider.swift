import AppKit

/// System-wide Now Playing info (Spotify, Music, browsers, …).
///
/// Since macOS 15.4 only Apple-entitled processes may use MediaRemote, so this
/// runs the bundled MediaRemoteAdapter through /usr/bin/perl, which is entitled,
/// and reads its JSON-lines stream.
final class MediaRemoteProvider: PlaybackProvider {
    var onUpdate: ((PlaybackSnapshot?) -> Void)?

    /// Sessions for which this returns false are reported as "nothing playing".
    private let filter: ((Track) -> Bool)?
    private var process: Process?
    private var isRunning = false
    private let reader = StreamReader()

    // MRCommand IDs understood by the adapter's `send` function.
    private enum Command: Int {
        case togglePlayPause = 2, nextTrack = 4, previousTrack = 5
    }

    init(filter: ((Track) -> Bool)? = nil) {
        self.filter = filter
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launchStream()
    }

    func stop() {
        isRunning = false
        process?.terminate()
        process = nil
    }

    func togglePlayPause() { run(["send", String(Command.togglePlayPause.rawValue)]) }
    func nextTrack() { run(["send", String(Command.nextTrack.rawValue)]) }
    func previousTrack() { run(["send", String(Command.previousTrack.rawValue)]) }
    func seek(to seconds: Double) { run(["seek", String(Int(seconds * 1_000_000))]) }

    // MRMediaRemote shuffle mode 1 = off, 3 = songs; repeat mode 1 = off, 2 = one, 3 = all.
    func setShuffle(_ enabled: Bool) { run(["shuffle", enabled ? "3" : "1"]) }

    func setRepeat(_ mode: RepeatMode) {
        let value = switch mode {
        case .off: "1"
        case .one: "2"
        case .all: "3"
        }
        run(["repeat", value])
    }

    // MARK: - Adapter process

    private static let adapterPaths: (script: String, framework: String)? = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/MediaRemoteAdapter"),
        ].compactMap { $0 }

        for dir in candidates {
            let script = dir.appendingPathComponent("mediaremote-adapter.pl").path
            let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework").path
            if FileManager.default.fileExists(atPath: script),
               FileManager.default.fileExists(atPath: framework) {
                return (script, framework)
            }
        }
        return nil
    }()

    private func makeProcess(_ arguments: [String]) -> Process? {
        guard let paths = Self.adapterPaths else {
            NSLog("Lenotch: MediaRemoteAdapter not found in bundle")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework] + arguments
        process.standardError = FileHandle.nullDevice
        return process
    }

    private func launchStream() {
        guard isRunning, let process = makeProcess(["stream", "--no-diff", "--debounce=50"]) else { return }

        let pipe = Pipe()
        process.standardOutput = pipe
        reader.reset()
        pipe.fileHandleForReading.readabilityHandler = { [weak self, reader] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let snapshots = reader.consume(data)
            guard !snapshots.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                snapshots.forEach(self.emit)
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.isRunning, self.process === process else { return }
                self.launchStream()
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Lenotch: failed to start MediaRemoteAdapter: \(error)")
        }
    }

    private func emit(_ snapshot: PlaybackSnapshot?) {
        if let snapshot, let filter, !filter(snapshot.track) {
            onUpdate?(nil)
        } else {
            onUpdate?(snapshot)
        }
    }

    private func run(_ arguments: [String]) {
        guard let process = makeProcess(arguments) else { return }
        process.standardOutput = FileHandle.nullDevice
        try? process.run()
    }
}

/// Splits the adapter's stdout into JSON lines and decodes them off the main thread.
/// Only touched from the pipe's serial readability handler.
private final class StreamReader: @unchecked Sendable {
    private struct Line: Decodable {
        let type: String
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let album: String?
        let duration: Double?
        let elapsedTime: Double?
        let timestamp: String?
        let playbackRate: Double?
        let playing: Bool?
        let shuffleMode: Int?
        let repeatMode: Int?
        let artworkData: String?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
    }

    private var buffer = Data()
    /// Hash of the last artwork's base64 text, so it's only decoded when it changes.
    private var lastArtworkHash: Int?
    private var artwork: NSImage?
    private let dateFormatter = ISO8601DateFormatter()

    func reset() {
        buffer.removeAll()
        lastArtworkHash = nil
        artwork = nil
    }

    func consume(_ data: Data) -> [PlaybackSnapshot?] {
        buffer.append(data)
        var snapshots: [PlaybackSnapshot?] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let decoded = try? JSONDecoder().decode(Line.self, from: line),
                  decoded.type == "data", let payload = decoded.payload else { continue }
            snapshots.append(snapshot(from: payload))
        }
        return snapshots
    }

    private func snapshot(from payload: Payload) -> PlaybackSnapshot? {
        guard let title = payload.title, !title.isEmpty else { return nil }

        let artworkHash = payload.artworkData?.hashValue
        if artworkHash != lastArtworkHash {
            lastArtworkHash = artworkHash
            artwork = payload.artworkData
                .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
                .flatMap { ImageDownsampling.image(from: $0) }
        }

        let track = Track(title: title,
                          artist: payload.artist ?? "",
                          album: payload.album ?? "",
                          duration: payload.duration ?? 0,
                          bundleIdentifier: payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier)
        return PlaybackSnapshot(track: track,
                                isPlaying: payload.playing ?? false,
                                elapsed: payload.elapsedTime ?? 0,
                                timestamp: payload.timestamp.flatMap(dateFormatter.date(from:)) ?? Date(),
                                rate: payload.playbackRate ?? 1,
                                artwork: artwork,
                                shuffle: payload.shuffleMode.flatMap { $0 > 0 ? $0 != 1 : nil },
                                repeatMode: payload.repeatMode.flatMap(Self.repeatMode))
    }

    private static func repeatMode(_ value: Int) -> RepeatMode? {
        switch value {
        case 1: .off
        case 2: .one
        case 3: .all
        default: nil
        }
    }
}
