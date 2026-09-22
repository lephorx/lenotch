import CoreGraphics
import Foundation

/// Display brightness has no public API on Apple Silicon. DisplayServices is a private
/// system framework that every brightness utility on the platform uses; we dlopen it so a
/// missing or renamed symbol degrades to "brightness unavailable" instead of failing to launch.
final class BrightnessService: @unchecked Sendable {
    static let shared = BrightnessService()

    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var getFn: GetFn?
    private var setFn: SetFn?

    private(set) var isAvailable = false

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        self.handle = handle
        if let get = dlsym(handle, "DisplayServicesGetBrightness"),
           let set = dlsym(handle, "DisplayServicesSetBrightness") {
            getFn = unsafeBitCast(get, to: GetFn.self)
            setFn = unsafeBitCast(set, to: SetFn.self)
            isAvailable = true
        }
    }

    private var display: CGDirectDisplayID { CGMainDisplayID() }

    var brightness: Float {
        get {
            guard let getFn else { return 0 }
            var value: Float = 0
            return getFn(display, &value) == 0 ? value : 0
        }
        set {
            guard let setFn else { return }
            _ = setFn(display, min(max(newValue, 0), 1))
        }
    }

    func step(by delta: Float) {
        guard isAvailable else { return }
        brightness = min(max(brightness + delta, 0), 1)
    }
}
