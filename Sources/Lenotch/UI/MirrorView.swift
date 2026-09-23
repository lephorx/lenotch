import AVFoundation
import SwiftUI

/// Camera popup beside the notch: hangs from the top of the screen like a small
/// notch and slides down when shown. Styled like the notch (black or glass).
struct MirrorPopup: View {
    let model: NotchViewModel

    var body: some View {
        ZStack(alignment: .top) {
            if model.isMirrorVisible {
                let shape = NotchShape(topRadius: NotchShape.mirrorTopRadius,
                                       bottomRadius: NotchShape.mirrorBottomRadius)
                MirrorView(camera: model.camera)
                    .padding(.horizontal, NotchShape.mirrorTopRadius + 10)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background {
                        NotchBackground(appearance: model.settings.appearance, gradient: model.backgroundGradient,
                                        isOpen: true, notchHeight: model.geometry.notchSize.height, shape: shape)
                    }
                    .clipShape(shape)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// Live, mirrored front-camera preview.
struct MirrorView: View {
    let camera: CameraMirror

    private static let cornerRadius: CGFloat = 24

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(.white.opacity(0.06))
            switch camera.status {
            case .running:
                CameraPreview(previewLayer: camera.previewLayer, cornerRadius: Self.cornerRadius)
                    .transition(.opacity)
            case .idle:
                ProgressView().controlSize(.small)
            case .denied:
                message(symbol: "video.slash", text: "Camera access is off") {
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                }
            case .unavailable:
                message(symbol: "video.slash", text: "No camera found") { EmptyView() }
            }
        }
        .animation(.easeOut(duration: 0.25), value: camera.status)
    }

    private func message<Action: View>(symbol: String, text: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(text).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.center)
            action()
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(8)
    }
}

/// Shows the camera's shared preview layer, mirrored like a real mirror. The layer
/// is moved into whichever popup is showing, follows its size, and rounds its own
/// corners since SwiftUI clipping doesn't reliably apply to AppKit layers.
private struct CameraPreview: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(previewLayer: previewLayer, cornerRadius: cornerRadius)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.adoptLayer()
    }

    final class PreviewView: NSView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer, cornerRadius: CGFloat) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.cornerRadius = cornerRadius
            previewLayer.cornerCurve = .continuous
            previewLayer.masksToBounds = true
            adoptLayer()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// Takes the shared layer from a previous popup, if it still holds it.
        func adoptLayer() {
            guard let layer, previewLayer.superlayer !== layer else { return }
            previewLayer.removeFromSuperlayer()
            layer.addSublayer(previewLayer)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            // An older popup that's still animating out must not resize the shared layer.
            guard previewLayer.superlayer === layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
            // The connection may only exist once the session has started.
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported,
               !connection.isVideoMirrored {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}
