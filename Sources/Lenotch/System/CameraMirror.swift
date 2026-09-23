import AVFoundation
import Observation

/// Front camera feed for the mirror popup. Runs only while the popup is showing.
@Observable
final class CameraMirror {
    enum Status { case idle, running, denied, unavailable }

    private(set) var status: Status = .idle
    @ObservationIgnored let session = AVCaptureSession()
    /// One preview layer for the camera's whole lifetime. A session doesn't reliably
    /// feed a second preview layer, so each popup reuses this one instead of making its own.
    @ObservationIgnored private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()
    @ObservationIgnored private let queue = DispatchQueue(label: "Lenotch.Camera")
    @ObservationIgnored private var isConfigured = false
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
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        if status == .running { status = .idle }
    }

    private func startSession() {
        guard wantsRunning else { return }
        queue.async { [self] in
            if !isConfigured {
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                    ?? AVCaptureDevice.default(for: .video)
                guard let device else {
                    NSLog("Lenotch: no camera found")
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw CocoaError(.featureUnsupported) }
                    session.beginConfiguration()
                    session.sessionPreset = .high
                    session.addInput(input)
                    session.commitConfiguration()
                } catch {
                    NSLog("Lenotch: camera input failed: \(error)")
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                isConfigured = true
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async {
                // The popup may have closed while the camera was starting.
                if self.wantsRunning {
                    self.status = .running
                } else {
                    self.stop()
                }
            }
        }
    }
}
