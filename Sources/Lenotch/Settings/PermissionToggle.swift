import SwiftUI

/// A feature switch that needs a macOS permission. It only shows as on when the
/// feature is enabled *and* allowed. Turning it on asks macOS right away (or opens
/// System Settings when access was denied before).
struct PermissionToggle: View {
    let title: String
    @Binding var isEnabled: Bool
    let status: PermissionCenter.Status
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: Binding(
                get: { isEnabled && status == .granted },
                set: { turnOn in
                    isEnabled = turnOn
                    guard turnOn else { return }
                    switch status {
                    case .granted: break
                    case .notAsked: request()
                    case .denied, .needsAppOpen: openSettings()
                    }
                }))
            if isEnabled, status == .denied {
                Text("Access was denied — allow Lenotch in System Settings, then come back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension PermissionCenter {
    func toggle(_ title: String, isEnabled: Binding<Bool>, calendar kind: CalendarKind) -> PermissionToggle {
        switch kind {
        case .events:
            PermissionToggle(title: title, isEnabled: isEnabled, status: calendar, request: requestCalendar,
                             openSettings: { self.openPrivacySettings("Privacy_Calendars") })
        case .reminders:
            PermissionToggle(title: title, isEnabled: isEnabled, status: reminders, request: requestReminders,
                             openSettings: { self.openPrivacySettings("Privacy_Reminders") })
        }
    }

    func cameraToggle(_ title: String, isEnabled: Binding<Bool>) -> PermissionToggle {
        PermissionToggle(title: title, isEnabled: isEnabled, status: camera, request: requestCamera,
                         openSettings: { self.openPrivacySettings("Privacy_Camera") })
    }

    enum CalendarKind { case events, reminders }
}
