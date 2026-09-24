import SwiftUI

/// First-launch setup: pick an audio source, an appearance, then the permissions
/// for the features you want (nothing is asked for unless you click Allow).
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter
    let finish: () -> Void

    private static let lastStep = 2

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            header
            Group {
                switch step {
                case 0:
                    SourcePicker(selection: $settings.audioSource)
                        .transition(.push(from: .trailing).combined(with: .opacity))
                case 1:
                    AppearancePicker(settings: settings)
                        .transition(.push(from: .trailing).combined(with: .opacity))
                default:
                    PermissionsView(permissions: permissions, settings: settings)
                        .transition(.push(from: .trailing).combined(with: .opacity))
                }
            }
            .frame(minHeight: 170, alignment: .top)
            footer
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 560)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    private var header: some View {
        VStack(spacing: 8) {
            NotchShape(topRadius: 6, bottomRadius: 14)
                .fill(.black)
                .frame(width: 120, height: 30)
                .overlay(alignment: .trailing) {
                    EqualizerBars(isPlaying: true)
                        .frame(width: 14, height: 11)
                        .padding(.trailing, 16)
                }
                .padding(.bottom, 6)
            Text(["Welcome to Lenotch", "Choose a Style", "Permissions"][step])
                .font(.system(size: 22, weight: .bold))
            Text(["Which app should the notch show music from?",
                  "How should the notch look when it opens?",
                  "Allow only what you want to use. You can change this any time in Settings."][step])
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
                    .controlSize(.large)
            }
            Button(step < Self.lastStep ? "Continue" : "Get Started") {
                if step < Self.lastStep { step += 1 } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }
}
