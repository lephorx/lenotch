import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

/// A volume or brightness change to show in the notch.
struct SystemIndicator: Equatable {
    enum Kind: Equatable { case volume, brightness }

    let kind: Kind
    /// 0...1
    let level: Double
    var muted = false

    var symbol: String {
        switch kind {
        case .volume:
            if muted || level <= 0.001 { return "speaker.slash.fill" }
            return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}

/// Watches the output volume (Core Audio) and the built-in display's brightness
/// (DisplayServices), and reports changes. Neither needs a permission.
final class SystemIndicators {
    var onChange: ((SystemIndicator) -> Void)?
    var watchesVolume = false { didSet { watchesVolume ? startVolume() : stopVolume() } }
    var watchesBrightness = false { didSet { watchesBrightness ? startBrightness() : stopBrightness() } }

    // MARK: - Volume

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var lastVolume: (level: Float, muted: Bool)?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               scope: kAudioDevicePropertyScopeOutput)
    private static let muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)

    private func startVolume() {
        guard deviceListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice() }
        deviceListener = listener
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        attachToDefaultDevice()
    }

    private func stopVolume() {
        detachFromDevice()
        if let deviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        }
        deviceListener = nil
    }

    /// Follows the current output device (e.g. when AirPods connect).
    private func attachToDefaultDevice() {
        detachFromDevice()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return }
        device = id
        // Remember the current level so connecting a device doesn't flash the indicator.
        lastVolume = readVolume()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeDidChange() }
        volumeListener = listener
        var volume = Self.volumeAddress, mute = Self.muteAddress
        AudioObjectAddPropertyListenerBlock(id, &volume, .main, listener)
        AudioObjectAddPropertyListenerBlock(id, &mute, .main, listener)
    }

    private func detachFromDevice() {
        guard device != kAudioObjectUnknown, let volumeListener else { return }
        var volume = Self.volumeAddress, mute = Self.muteAddress
        AudioObjectRemovePropertyListenerBlock(device, &volume, .main, volumeListener)
        AudioObjectRemovePropertyListenerBlock(device, &mute, .main, volumeListener)
        self.volumeListener = nil
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func readVolume() -> (level: Float, muted: Bool)? {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.volumeAddress
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &level) == noErr else { return nil }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = Self.muteAddress
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return (level, muted != 0)
    }

    private func volumeDidChange() {
        guard let now = readVolume() else { return }
        defer { lastVolume = now }
        guard let last = lastVolume, abs(last.level - now.level) > 0.001 || last.muted != now.muted else { return }
        onChange?(SystemIndicator(kind: .volume, level: Double(now.level), muted: now.muted))
    }

    // MARK: - Brightness

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private var brightnessTimer: Timer?
    private var lastBrightness: Float?

    /// The built-in display, else the main one.
    private var display: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// macOS has no brightness-change notification for apps, so it's read 5× a second
    /// (a cheap call) only while the brightness indicator is on.
    private func startBrightness() {
        guard brightnessTimer == nil, Self.getBrightness != nil else { return }
        lastBrightness = readBrightness()
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.brightnessTick()
        }
    }

    private func stopBrightness() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
    }

    private func readBrightness() -> Float? {
        var value: Float = 0
        guard let get = Self.getBrightness, get(display, &value) == 0 else { return nil }
        return value
    }

    private func brightnessTick() {
        guard let now = readBrightness() else { return }
        defer { lastBrightness = now }
        guard let last = lastBrightness, abs(last - now) > 0.004 else { return }
        onChange?(SystemIndicator(kind: .brightness, level: Double(now)))
    }
}
