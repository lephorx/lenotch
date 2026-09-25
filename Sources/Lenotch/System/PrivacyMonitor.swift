import AppKit
import CoreAudio
import CoreMediaIO

/// Which apps are using the microphone, and whether a camera is on, like macOS's
/// orange and green dots. Reading this doesn't need any permission.
struct PrivacyActivity: Equatable {
    /// Bundle identifiers of apps recording from a microphone (may be empty when
    /// the mic is on but the app can't be told, e.g. on macOS 14.0/14.1).
    var micApps: [String] = []
    var isMicOn = false
    var isCameraOn = false

    var isEmpty: Bool { !isMicOn && !isCameraOn }
}

final class PrivacyMonitor {
    var onChange: ((PrivacyActivity) -> Void)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled { start() } else { stop() }
        }
    }

    private var timer: Timer?
    private var current = PrivacyActivity()

    /// Polled once a second; there's no single notification for "any app started recording".
    private func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if !current.isEmpty {
            current = PrivacyActivity()
            onChange?(current)
        }
    }

    private func tick() {
        var activity = PrivacyActivity()
        if #available(macOS 14.2, *) {
            activity.micApps = Self.appsRecording()
            activity.isMicOn = !activity.micApps.isEmpty
        } else {
            activity.isMicOn = Self.isDefaultInputRunning()
        }
        activity.isCameraOn = Self.isCameraRunning()
        guard activity != current else { return }
        current = activity
        onChange?(activity)
    }

    // MARK: - Microphone

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    @available(macOS 14.2, *)
    private static func appsRecording() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [String] = []
        for process in processes where uint32(process, kAudioProcessPropertyIsRunningInput) == 1 {
            // Lenotch's own audio tap (the visualizer) doesn't count.
            if let pid = uint32(process, kAudioProcessPropertyPID), pid_t(pid) == ownPID { continue }
            var bundleAddress = Self.address(kAudioProcessPropertyBundleID)
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let id = AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundleID) == noErr
                ? bundleID?.takeRetainedValue() as String? : nil
            apps.append(id ?? "")
        }
        return apps
    }

    private static func isDefaultInputRunning() -> Bool {
        var address = address(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr
        else { return false }
        return uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
    }

    // MARK: - Camera

    private static func cmioAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func isCameraRunning() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = cmioAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }
        return devices.contains { device in
            var running = cmioAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var valueUsed: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size),
                                             &valueUsed, &value) == noErr && value != 0
        }
    }
}
