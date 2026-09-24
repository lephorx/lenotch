import AppKit
import SwiftUI

/// Click, then press a key combination (with ⌘, ⌥ or ⌃) to set a shortcut.
/// Delete clears it, Escape cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    let defaultShortcut: KeyShortcut

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stop() : start()
            } label: {
                Text(isRecording ? "Press keys…" : shortcut?.display ?? "Off")
                    .monospaced()
                    .frame(minWidth: 70)
            }
            if shortcut != defaultShortcut {
                Button("Reset") { shortcut = defaultShortcut }.buttonStyle(.borderless)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53:  // Escape
                stop()
            case 51, 117:  // Delete, Forward Delete
                shortcut = nil
                stop()
            default:
                guard let recorded = KeyShortcut(event: event) else { return nil }
                shortcut = recorded
                stop()
            }
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
