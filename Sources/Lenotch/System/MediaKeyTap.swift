import AppKit
import CoreGraphics

/// Catches the volume and brightness keys (needs Accessibility) so Lenotch can make
/// the change itself and macOS doesn't show its own indicator.
final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    /// Handles a key press; returns false to let macOS handle it instead
    /// (e.g. when the output's volume can't be set). `fine` is Option+Shift (quarter steps).
    var onKey: ((Key, _ fine: Bool) -> Bool)?
    /// Which keys to take over.
    var handlesVolume = false
    var handlesBrightness = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// Starts the tap if Accessibility is allowed; never asks.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }
        // NX_SYSDEFINED (14) carries the media keys; some keyboards send brightness as key downs.
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let this = Unmanaged<MediaKeyTap>.fromOpaque(info).takeUnretainedValue()
                return this.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .keyDown, .keyUp:
            // Brightness keys on some keyboards: 144 up, 145 down.
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let key: Key? = code == 144 ? .brightnessUp : code == 145 ? .brightnessDown : nil
            guard let key, handlesBrightness else { return pass }
            if type == .keyUp { return nil }
            return press(key, flags: event.flags) ? nil : pass
        default:
            guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
            let keyCode = (ns.data1 & 0xFFFF0000) >> 16
            let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
            let key: Key
            switch keyCode {
            case 0 where handlesVolume: key = .volumeUp          // NX_KEYTYPE_SOUND_UP
            case 1 where handlesVolume: key = .volumeDown        // NX_KEYTYPE_SOUND_DOWN
            case 7 where handlesVolume: key = .mute              // NX_KEYTYPE_MUTE
            case 2 where handlesBrightness: key = .brightnessUp  // NX_KEYTYPE_BRIGHTNESS_UP
            case 3 where handlesBrightness: key = .brightnessDown
            default: return pass
            }
            // Key ups are swallowed with their downs; macOS shows its indicator on the down.
            guard isDown else { return nil }
            return press(key, flags: event.flags) ? nil : pass
        }
    }

    private func press(_ key: Key, flags: CGEventFlags) -> Bool {
        let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
        return onKey?(key, fine) ?? false
    }
}
