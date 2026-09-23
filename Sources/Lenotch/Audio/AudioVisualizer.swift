import AudioToolbox
import CoreAudio
import Foundation

/// Live frequency levels of the Mac's audio output, from a Core Audio process tap
/// (macOS 14.2+). macOS asks once for permission to record system audio; if it's
/// denied the tap only delivers silence and `hasSignal` stays false.
final class AudioVisualizer: @unchecked Sendable {
    private let lock = NSLock()
    private var currentLevels = [Float](repeating: 0, count: SpectrumAnalyzer.bands.count)
    private var lastSignal = Date.distantPast

    private let queue = DispatchQueue(label: "Lenotch.AudioTap", qos: .userInteractive)
    /// Creating and destroying the tap can block for a long time (e.g. while macOS
    /// waits on the permission prompt), so it never happens on the main thread.
    private let controlQueue = DispatchQueue(label: "Lenotch.AudioTapControl")
    /// After a failed start, don't retry before this time.
    private var retryAfter = Date.distantPast
    private let analyzer = SpectrumAnalyzer()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var format = AudioStreamBasicDescription()
    private var outputListener: AudioObjectPropertyListenerBlock?

    /// Whether the visualizer should be running (main thread); the tap itself
    /// is started and stopped asynchronously on `controlQueue`.
    private(set) var isRunning = false

    /// Levels 0...1 for each band, bass to treble. Safe to call from any thread.
    var levels: [Float] {
        lock.withLock { currentLevels }
    }

    /// Whether real audio arrived recently (false while silent or without permission).
    var hasSignal: Bool {
        lock.withLock { Date().timeIntervalSince(lastSignal) < 1.5 }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning, Date() > retryAfter, #available(macOS 14.2, *) else { return }
        isRunning = true
        watchOutputDevice()
        controlQueue.async { [self] in
            do {
                try startTap()
            } catch {
                NSLog("Lenotch: audio tap failed: \(error)")
                tearDown()
                DispatchQueue.main.async {
                    self.retryAfter = Date().addingTimeInterval(30)
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        unwatchOutputDevice()
        controlQueue.async { [self] in
            tearDown()
            lock.withLock {
                currentLevels = currentLevels.map { _ in 0 }
                lastSignal = .distantPast
            }
        }
    }

    // MARK: - Tap

    private struct TapError: Error {
        let step: String
        let status: OSStatus
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        if status != noErr { throw TapError(step: step, status: status) }
    }

    @available(macOS 14.2, *)
    private func startTap() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Lenotch Visualizer"
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create tap")

        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var formatAddress = Self.address(kAudioTapPropertyFormat)
        try check(AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &format), "tap format")

        let outputUID = try defaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lenotch Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create aggregate")

        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            self?.handle(input)
        }, "create io proc")
        try check(AudioDeviceStart(aggregateID, procID), "start device")
    }

    private func tearDown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Mixes the tap's buffers down to mono and feeds the analyzer. Runs on `queue`.
    private func handle(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }

        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = max(Int(nonInterleaved ? buffers.count : Int(first.mNumberChannels)), 1)
        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size / (nonInterleaved ? 1 : channels)
        guard frames > 0 else { return }

        var mono = [Float](repeating: 0, count: frames)
        if nonInterleaved {
            for buffer in buffers {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<frames { mono[frame] += samples[frame] / Float(channels) }
            }
        } else {
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                mono[frame] = sum / Float(channels)
            }
        }

        let peak = mono.lazy.map(abs).max() ?? 0
        let sampleRate = Float(format.mSampleRate > 0 ? format.mSampleRate : 48_000)
        guard mono.withUnsafeBufferPointer({ analyzer.process($0, sampleRate: sampleRate) }) else { return }

        let newLevels = analyzer.levels
        lock.withLock {
            currentLevels = newLevels
            if peak > 0.0005 { lastSignal = Date() }
        }
    }

    // MARK: - Output device

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                             &size, &deviceID), "default output")
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address = Self.address(kAudioDevicePropertyDeviceUID)
        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid), "output uid")
        guard let uid else { throw TapError(step: "output uid", status: -1) }
        return uid.takeRetainedValue() as String
    }

    /// Rebuilds the tap when the output device changes (e.g. AirPods connect).
    private func watchOutputDevice() {
        var address = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                self.stop()
                self.start()
            }
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    private func unwatchOutputDevice() {
        guard let listener = outputListener else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        outputListener = nil
    }
}
