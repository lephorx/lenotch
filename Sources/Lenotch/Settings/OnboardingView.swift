import SwiftUI

/// First-launch setup: pick an audio source, then an appearance.
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let finish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            header
            Group {
                if step == 0 {
                    SourcePicker(selection: $settings.audioSource)
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading))
                            .combined(with: .opacity))
                } else {
                    AppearancePicker(settings: settings)
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing))
                            .combined(with: .opacity))
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
            Text(step == 0 ? "Welcome to Lenotch" : "Choose a Style")
                .font(.system(size: 22, weight: .bold))
            Text(step == 0
                 ? "Which app should the notch show music from?"
                 : "How should the notch look when it opens?")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<2) { index in
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
            Button(step == 0 ? "Continue" : "Get Started") {
                if step == 0 { step += 1 } else { finish() }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
    }
}
