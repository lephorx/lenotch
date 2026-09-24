import AVFoundation
import Observation

/// Front camera feed for the mirror popup.
///
/// A capture session (and its preview layer) is created when the mirror opens and
/// released completely when it closes, so the camera — and the Neural Engine memory
/// macOS's video effects allocate for it — is only held while the mirror is showing.
/// Each opening gets a fresh session and layer, so a popup still animating out
/// can never hold on to the new one.
@Observable
final class CameraMirror {
    enum Status { case idle, running, denied, unavailable }

    private(set) var status: Status = .idle
    /// Valid while `status` is `.running`.
    @ObservationIgnored private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    @ObservationIgnored private var session: AVCaptureSession?
    @ObservationIgnored private let queue = DispatchQueue(label: "Lenotch.Camera")
    @ObservationIgnored private var wantsRunning = false

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.startSession() } else { self.status = .denied }
                }
            }
        default:
            NSLog("Lenotch: camera access denied")
            status = .denied
        }
    }

    func stop() {
        wantsRunning = false
        if status == .running { status = .idle }
        guard let session else { return }
        self.session = nil
        previewLayer = nil
        // Stop off the main thread; the session is released when this block finishes.
        queue.async {
            if session.isRunning { session.stopRunning() }
            session.inputs.forEach(session.removeInput)
        }
    }

    private func startSession() {
        guard wantsRunning, session == nil else { return }
        // A mirror should show you as you are: no Center Stage cropping. (Gesture
        // reactions are off by default via NSCameraReactionEffectGesturesEnabledDefault,
        // which also keeps their hand-tracking models out of memory.)
        if AVCaptureDevice.centerStageControlMode != .app {
            AVCaptureDevice.centerStageControlMode = .app
        }
        AVCaptureDevice.isCenterStageEnabled = false
        let session = AVCaptureSession()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        self.session = session
        previewLayer = layer

        queue.async { [weak self] in
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
            guard let device else {
                NSLog("Lenotch: no camera found")
                DispatchQueue.main.async { self?.status = .unavailable }
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
                session.beginConfiguration()
                // The popup is ~150 pt, so a small preset saves memory and power.
                session.sessionPreset = session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
                session.addInput(input)
                session.commitConfiguration()
            } catch {
                NSLog("Lenotch: camera input failed: \(error)")
                DispatchQueue.main.async { self?.status = .unavailable }
                return
            }
            session.startRunning()
            DispatchQueue.main.async {
                // Ignore if the mirror was closed (or reopened with a new session) meanwhile.
                guard let self, self.session === session else { return }
                self.status = .running
            }
        }
    }
}
