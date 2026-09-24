import AppKit
import Carbon.HIToolbox

/// A key combination for a global shortcut (Carbon key code + modifiers).
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    /// What the key itself shows, e.g. "I".
    var key: String

    static let toggleDefault = KeyShortcut(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(cmdKey | shiftKey), key: "I")
    static let peekDefault = KeyShortcut(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | shiftKey), key: "O")

    /// E.g. "⌘⇧I".
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// From a key press in the shortcut recorder; nil without ⌘, ⌃ or ⌥.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return nil }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }
}

/// System-wide shortcuts via Carbon hot keys, which need no Accessibility permission.
final class HotKeyCenter {
    private var handlers: [UInt32: () -> Void] = [:]
    private var references: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { center.handlers[id.id]?() }
            return noErr
        }, 1, &type, context, &eventHandler)
    }

    deinit {
        references.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Registers (or replaces) the shortcut with the given id.
    func register(_ shortcut: KeyShortcut, id: UInt32, action: @escaping () -> Void) {
        unregister(id: id)
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4E_5448), id: id)  // 'LNTH'
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(),
                                  0, &reference) == noErr, let reference else {
            NSLog("Lenotch: couldn't register shortcut \(shortcut.display) (already taken?)")
            return
        }
        references[id] = reference
        handlers[id] = action
    }

    func unregister(id: UInt32) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        handlers[id] = nil
    }
}
