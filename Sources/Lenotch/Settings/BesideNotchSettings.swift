import SwiftUI

/// Volume and brightness levels beside the notch, optionally instead of macOS's own.
struct VolumeBrightnessSettings: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter

    var body: some View {
        Form {
            Section {
                Toggle("Volume", isOn: $settings.showVolumeIndicator)
                Toggle("Brightness", isOn: $settings.showBrightnessIndicator)
            } header: {
                Text("Show changes beside the notch")
            } footer: {
                Text("The level appears beside the notch for a moment when it changes.")
            }
            Section {
                permissions.accessibilityToggle("Hide the macOS indicator", isEnabled: $settings.hideSystemIndicator)
                    .disabled(!settings.showVolumeIndicator && !settings.showBrightnessIndicator)
            } footer: {
                Text("Needs Accessibility, so Lenotch can handle the volume and brightness keys itself and only its own indicator shows.")
            }
        }
        .formStyle(.grouped)
    }
}

/// The orange/green outline while an app uses the microphone or camera.
struct MicCameraSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Outline while in use", isOn: $settings.showPrivacyIndicator)
                Toggle("Glow", isOn: $settings.privacyGlow)
                    .disabled(!settings.showPrivacyIndicator)
            } footer: {
                Text("Orange around the notch while an app uses the microphone, green for the camera, both during a video call. The glow adds a soft halo. No permission needed.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Download and upload speed while a big transfer runs.
struct NetworkSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Speed during downloads and uploads", isOn: $settings.showNetworkSpeed)
            } footer: {
                Text("Shows beside the notch while more than about 1 MB/s is moving and no music or timer is showing. No permission needed.")
            }
        }
        .formStyle(.grouped)
    }
}

/// The timer button in the open notch and its alarm.
struct TimerSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Timer button in the notch", isOn: $settings.showTimer)
            } footer: {
                Text("Start a timer from the button next to the gear. It counts down beside the notch, and when it ends the notch folds down with the alarm.")
            }
            Section {
                Toggle("Silent timers", isOn: $settings.timerSilent)
            } header: {
                Text("Alarm")
            } footer: {
                Text("The alarm rings for 10 seconds or until you click ×. Silent timers still fold the notch down, just without the sound. You can also switch this with the bell in the timer.")
            }
            .disabled(!settings.showTimer)
        }
        .formStyle(.grouped)
    }
}
