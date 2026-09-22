import AppKit
import SwiftUI

enum HUDKind: Equatable {
    case volume(Float, muted: Bool)
    case brightness(Float)

    var symbol: String {
        switch self {
        case .volume(let value, let muted):
            if muted || value == 0 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness(let value):
            return value < 0.45 ? "sun.min.fill" : "sun.max.fill"
        }
    }

    var value: Float {
        switch self {
        case .volume(let value, let muted): return muted ? 0 : value
        case .brightness(let value): return value
        }
    }

    var title: String {
        switch self {
        case .volume(_, let muted): return muted ? "Muted" : "Volume"
        case .brightness: return "Brightness"
        }
    }

    /// Two HUDs of the same kind replace each other; different kinds cut over immediately.
    func sameKind(as other: HUDKind) -> Bool {
        switch (self, other) {
        case (.volume, .volume), (.brightness, .brightness): return true
        default: return false
        }
    }
}

/// Owns the custom volume/brightness HUD: listens for the hardware keys, applies the change
/// itself, and asks the notch to show the readout.
@MainActor
final class SystemHUDController: ObservableObject {
    @Published private(set) var current: HUDKind?
    @Published private(set) var hasAccessibilityPermission = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dismissTask: Task<Void, Never>?
    private var suppressionTimer: Timer?

    init() {
        hasAccessibilityPermission = AXIsProcessTrusted()

        // When we can't grab the keys, still mirror volume changes the system makes so the
        // HUD is useful before the user grants Accessibility.
        AudioService.shared.onChange = { [weak self] volume, muted in
            guard let self else { return }
            Task { @MainActor in
                guard !self.hasAccessibilityPermission else { return }
                self.show(.volume(volume, muted: muted))
            }
        }

        if hasAccessibilityPermission { installTap() }
        applySuppressionSetting()
    }

    deinit {
        suppressionTimer?.invalidate()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // The prompt is modal to System Settings; poll until it flips, then install the tap.
        Task { @MainActor in
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if AXIsProcessTrusted() {
                    hasAccessibilityPermission = true
                    installTap()
                    return
                }
            }
        }
    }

    func show(_ kind: HUDKind) {
        guard Settings.shared.replaceSystemHUD else { return }
        current = kind
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.hud) { self.current = nil }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }

    // MARK: - Hiding the built-in HUD

    func applySuppressionSetting() {
        suppressionTimer?.invalidate()
        suppressionTimer = nil
        guard Settings.shared.suppressMacOSHUD else { return }
        // OSDUIHelper is relaunched on demand by the system, so the only way to keep the
        // stock HUD off screen is to keep retiring it. It costs nothing when it isn't running.
        let timer = Timer(timeInterval: 2.0, repeats: true) { _ in
            let task = Process()
            task.launchPath = "/usr/bin/pkill"
            task.arguments = ["-f", "OSDUIHelper"]
            task.standardError = FileHandle.nullDevice
            try? task.run()
        }
        RunLoop.main.add(timer, forMode: .common)
        suppressionTimer = timer
    }

    // MARK: - Media key tap

    private func installTap() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << NX_SYSDEFINED)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<SystemHUDController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon)
        else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    /// Runs on the event tap's thread, not the main actor.
    nonisolated fileprivate func handle(proxy: CGEventTapProxy,
                                        type: CGEventType,
                                        event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == UInt32(NX_SYSDEFINED),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF0000) >> 16)
        let keyFlags = data & 0x0000FFFF
        let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        let isRepeat = (keyFlags & 0x1) == 1

        guard isKeyDown else { return Unmanaged.passUnretained(event) }

        let fineGrained = nsEvent.modifierFlags.contains(.option) && nsEvent.modifierFlags.contains(.shift)
        let stepSize: Float = fineGrained ? 1.0 / 64.0 : 1.0 / 16.0

        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            Task { @MainActor in self.adjustVolume(by: stepSize) }
        case NX_KEYTYPE_SOUND_DOWN:
            Task { @MainActor in self.adjustVolume(by: -stepSize) }
        case NX_KEYTYPE_MUTE:
            guard !isRepeat else { return nil }
            Task { @MainActor in self.toggleMute() }
        case NX_KEYTYPE_BRIGHTNESS_UP:
            guard BrightnessService.shared.isAvailable else { return Unmanaged.passUnretained(event) }
            Task { @MainActor in self.adjustBrightness(by: stepSize) }
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            guard BrightnessService.shared.isAvailable else { return Unmanaged.passUnretained(event) }
            Task { @MainActor in self.adjustBrightness(by: -stepSize) }
        default:
            return Unmanaged.passUnretained(event)
        }

        // Swallow the key so macOS never draws its own HUD for it.
        return nil
    }

    private func adjustVolume(by delta: Float) {
        AudioService.shared.step(by: delta)
        show(.volume(AudioService.shared.volume, muted: AudioService.shared.isMuted))
    }

    private func toggleMute() {
        AudioService.shared.toggleMute()
        show(.volume(AudioService.shared.volume, muted: AudioService.shared.isMuted))
    }

    private func adjustBrightness(by delta: Float) {
        BrightnessService.shared.step(by: delta)
        show(.brightness(BrightnessService.shared.brightness))
    }
}
