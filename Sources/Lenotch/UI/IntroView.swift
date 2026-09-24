import SwiftUI

/// First-launch intro inside the notch: the logo drops down from behind the
/// hardware notch, the name slides in, a shine sweeps across, then it all
/// shrinks away and `onFinish` closes the notch.
struct IntroView: View {
    let notchHeight: CGFloat
    let onFinish: () -> Void

    @State private var logoDropped = false
    @State private var glowing = false
    @State private var showTitle = false
    @State private var shine = false
    @State private var leaving = false

    private static let logoHeight: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
            HStack(spacing: 14) {
                logo
                Text("Lenotch")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(showTitle ? 1 : 0)
                    .blur(radius: showTitle ? 0 : 8)
                    .offset(x: showTitle ? 0 : -14)
            }
            .scaleEffect(leaving ? 0.7 : 1)
            .opacity(leaving ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await play() }
    }

    @ViewBuilder
    private var logo: some View {
        let size = CGSize(width: Self.logoHeight * LogoShape.aspectRatio, height: Self.logoHeight)
        Group {
            if let image = AppLogo.image {
                Image(nsImage: image).resizable()
                    .overlay {
                        // Shine band sweeping across, limited to the logo's shape.
                        GeometryReader { proxy in
                            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: proxy.size.width * 0.5)
                                .rotationEffect(.degrees(20))
                                .offset(x: shine ? proxy.size.width * 1.2 : -proxy.size.width * 0.7)
                        }
                        .mask(Image(nsImage: image).resizable())
                        .blendMode(.plusLighter)
                    }
            } else {
                LogoShape().fill(.white)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .white.opacity(glowing ? 0.6 : 0), radius: glowing ? 16 : 4)
        // Starts hidden above, behind the hardware notch, tilted.
        .offset(y: logoDropped ? 0 : -(notchHeight + Self.logoHeight + 20))
        .rotationEffect(.degrees(logoDropped ? 0 : -14))
    }

    private func play() async {
        // The view can disappear mid-replay; canceled sleeps must not advance
        // its animation or close a newer intro.
        guard (try? await Task.sleep(for: .milliseconds(380))) != nil else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { logoDropped = true }
        guard (try? await Task.sleep(for: .milliseconds(320))) != nil else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        withAnimation(.easeOut(duration: 0.6)) { glowing = true }
        guard (try? await Task.sleep(for: .milliseconds(200))) != nil else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { showTitle = true }
        withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { shine = true }
        guard (try? await Task.sleep(for: .milliseconds(1600))) != nil else { return }
        withAnimation(.easeIn(duration: 0.3)) {
            leaving = true
            glowing = false
        }
        guard (try? await Task.sleep(for: .milliseconds(260))) != nil else { return }
        onFinish()
    }
}
