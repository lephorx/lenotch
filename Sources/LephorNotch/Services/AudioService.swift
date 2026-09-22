import CoreAudio
import AudioToolbox
import Foundation

/// Reads and writes the default output device's master volume, and reports changes made by
/// anyone (the system HUD, a keyboard key, another app) via a CoreAudio property listener.
final class AudioService: @unchecked Sendable {
    static let shared = AudioService()

    var onChange: ((Float, Bool) -> Void)?

    private var deviceID = AudioDeviceID(0)
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        deviceID = Self.defaultOutputDevice()
        installListeners()
    }

    // MARK: - Volume

    var volume: Float {
        get { Self.readVolume(deviceID) }
        set { Self.writeVolume(deviceID, value: newValue) }
    }

    var isMuted: Bool {
        get { Self.readMute(deviceID) }
        set { Self.writeMute(deviceID, value: newValue) }
    }

    func step(by delta: Float) {
        let next = min(max(volume + delta, 0), 1)
        if next > 0 && isMuted { isMuted = false }
        volume = next
    }

    func toggleMute() { isMuted.toggle() }

    // MARK: - CoreAudio plumbing

    private static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return 0 }
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value
    }

    private static func writeVolume(_ device: AudioDeviceID, value: Float) {
        var value = Float32(min(max(value, 0), 1))
        var address = volumeAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private static func readMute(_ device: AudioDeviceID) -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return false }
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return value == 1
    }

    private static func writeMute(_ device: AudioDeviceID, value: Bool) {
        var raw = UInt32(value ? 1 : 0)
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return }
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &raw)
    }

    private func installListeners() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.onChange?(self.volume, self.isMuted)
        }
        listenerBlock = block

        var volume = Self.volumeAddress()
        var mute = Self.muteAddress()
        AudioObjectAddPropertyListenerBlock(deviceID, &volume, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(deviceID, &mute, DispatchQueue.main, block)

        // Re-bind when the user switches output device (headphones in/out, AirPlay, …).
        var defaultDevice = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultDevice, DispatchQueue.main) { [weak self] _, _ in
            guard let self else { return }
            self.rebind()
        }
    }

    private func rebind() {
        let old = deviceID
        guard let block = listenerBlock else { return }
        var volume = Self.volumeAddress()
        var mute = Self.muteAddress()
        AudioObjectRemovePropertyListenerBlock(old, &volume, DispatchQueue.main, block)
        AudioObjectRemovePropertyListenerBlock(old, &mute, DispatchQueue.main, block)

        deviceID = Self.defaultOutputDevice()
        AudioObjectAddPropertyListenerBlock(deviceID, &volume, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(deviceID, &mute, DispatchQueue.main, block)
        onChange?(self.volume, self.isMuted)
    }
}
