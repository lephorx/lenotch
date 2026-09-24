import SwiftUI

/// First-launch setup: a welcome screen, then pick an audio source, an appearance and
/// the permissions for the features you want (nothing is asked for unless you click Allow).
struct OnboardingView: View {
    @Bindable var settings: AppSettings
    let permissions: PermissionCenter
    let showAppearancePreview: () -> Void
    let hideAppearancePreview: () -> Void
    let finish: () -> Void

    private static let lastStep = 2

    @State private var step = 0
    @State private var showsWelcome = true

    var body: some View {
        ZStack {
            if showsWelcome {
                WelcomeScreen {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { showsWelcome = false }
                }
                .transition(.opacity.combined(with: .scale(0.97)))
            } else {
                steps
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(width: 560)
    }

    private var steps: some View {
        VStack(spacing: 20) {
            header
            Group {
                switch step {
                case 0:
                    SourcePicker(selection: $settings.audioSource)
                        .transition(.push(from: .trailing).combined(with: .opacity))
                case 1:
                    VStack(spacing: 14) {
                        AppearancePicker(settings: settings)
                        if settings.appearance == .glass {
                            glassOpacity
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: settings.appearance)
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .onChange(of: step) { oldStep, newStep in
            if newStep == 1 { showAppearancePreview() }
            else if oldStep == 1 { hideAppearancePreview() }
        }
        .onDisappear(perform: hideAppearancePreview)
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
            Text(["Your Music", "Choose a Style", "Permissions"][step])
                .font(.system(size: 22, weight: .bold))
            Text(["Which app should the notch show music from?",
                  "See the notch above as you choose its style and opacity.",
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

    /// How dark the glass gets towards the bottom (the glass style's "Bottom opacity").
    private var glassOpacity: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Glass opacity").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(settings.glassGradient.bottom.alpha, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text("Clear").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: $settings.glassGradient.bottom.alpha, in: 0...1)
                Text("Dark").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("How much the glass darkens towards the bottom. Higher is easier to read over bright or busy backgrounds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

/// The first thing a new user sees: the logo drops in, "Lenotch" slides in beside it
/// and a shine sweeps across, like the intro in the notch, then Get Started.
private struct WelcomeScreen: View {
    let getStarted: () -> Void

    @State private var logoDropped = false
    @State private var glowing = false
    @State private var showTitle = false
    @State private var shine = false
    @State private var showButton = false

    private static let logoHeight: CGFloat = 72

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.11)],
                                         startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [.white.opacity(glowing ? 0.10 : 0), .clear],
                               center: .center, startRadius: 0, endRadius: 220)
                HStack(spacing: 18) {
                    logo
                    Text("Lenotch")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(showTitle ? 1 : 0)
                        .blur(radius: showTitle ? 0 : 10)
                        .offset(x: showTitle ? 0 : -16)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 6) {
                Text("Your notch, made useful.")
                    .font(.system(size: 17, weight: .semibold))
                Text("Music, files, your calendar and more, right where the notch is.")
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .opacity(showButton ? 1 : 0)

            Button(action: getStarted) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 8)
        }
        .padding(.horizontal, 28)
        .padding(.top, 40)
        .padding(.bottom, 28)
        .task { await play() }
    }

    private var logo: some View {
        let size = CGSize(width: Self.logoHeight * LogoShape.aspectRatio, height: Self.logoHeight)
        return AppLogo(height: Self.logoHeight, glass: false)
            .overlay {
                // Shine band sweeping across, limited to the logo's shape.
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.5)
                        .rotationEffect(.degrees(20))
                        .offset(x: shine ? proxy.size.width * 1.2 : -proxy.size.width * 0.7)
                }
                .mask(LogoShape())
                .blendMode(.plusLighter)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .white.opacity(glowing ? 0.55 : 0), radius: glowing ? 18 : 4)
            .offset(y: logoDropped ? 0 : -150)
            .rotationEffect(.degrees(logoDropped ? 0 : -14))
            .opacity(logoDropped ? 1 : 0)
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.55, dampingFraction: 0.58)) { logoDropped = true }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeOut(duration: 0.6)) { glowing = true }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showTitle = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { shine = true }
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.easeOut(duration: 0.4)) { showButton = true }
    }
}
