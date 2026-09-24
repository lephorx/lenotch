import SwiftUI

/// Each permission with what it's for and an Allow button; macOS only asks when
/// the user clicks. Used in the setup window and in Settings.
struct PermissionsView: View {
    let permissions: PermissionCenter
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(spacing: 8) {
            row(symbol: "calendar", title: "Calendar",
                detail: "Your events next to the music.",
                status: permissions.calendar,
                allow: permissions.requestCalendar,
                pane: "Privacy_Calendars")
            row(symbol: "checklist", title: "Reminders",
                detail: "Due reminders from your selected lists.",
                status: permissions.reminders,
                allow: permissions.requestReminders,
                pane: "Privacy_Reminders")
            row(symbol: "camera.fill", title: "Camera",
                detail: "The mirror beside the notch.",
                status: permissions.camera,
                allow: permissions.requestCamera,
                pane: "Privacy_Camera")
            row(symbol: "waveform", title: "System audio recording",
                detail: "Bars that follow the real sound. Nothing is recorded.",
                status: settings.realAudioVisualizer ? .granted : .notAsked,
                grantedText: "On",
                allow: permissions.enableAudioVisualizer,
                pane: "Privacy_AudioCapture")
            ForEach(permissions.controllableApps) { app in
                row(symbol: "play.circle.fill", title: "Control \(app.name)",
                    detail: "Read and control \(app.name) directly.",
                    status: permissions.automation[app.id] ?? .notAsked,
                    allow: { permissions.requestAutomation(app) },
                    pane: "Privacy_Automation")
            }
        }
        .onAppear(perform: permissions.refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private func row(symbol: String, title: String, detail: String, status: PermissionCenter.Status,
                     grantedText: String = "Allowed", allow: @escaping () -> Void, pane: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            switch status {
            case .granted:
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
            case .denied:
                Button("Open Settings") { permissions.openPrivacySettings(pane) }
                    .controlSize(.small)
            case .needsAppOpen:
                Text("Open the app first").font(.system(size: 11)).foregroundStyle(.secondary)
            case .notAsked:
                Button("Allow", action: allow)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}
