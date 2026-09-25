import Darwin
import Foundation

/// Download and upload speed over Wi-Fi/Ethernet from the interface byte counters
/// (no permission). Reports `isBusy` while a sizeable download or upload runs.
final class NetworkMonitor {
    struct Speed: Equatable {
        /// Bytes per second.
        var down: Double
        var up: Double
    }

    /// `nil` when the network is quiet again.
    var onChange: ((Speed?) -> Void)?
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                last = Self.counters()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            } else {
                timer?.invalidate()
                timer = nil
                if isBusy { isBusy = false; onChange?(nil) }
            }
        }
    }

    /// Starts showing above 1 MB/s for 2 seconds, hides below 150 KB/s for 3 seconds.
    private static let startRate = 1_000_000.0, stopRate = 150_000.0
    private var timer: Timer?
    private var last: (down: UInt32, up: UInt32, time: Date)?
    private var fastSeconds = 0, slowSeconds = 0
    private var isBusy = false

    private func tick() {
        let now = Self.counters()
        defer { last = now }
        guard let last else { return }
        let seconds = max(now.time.timeIntervalSince(last.time), 0.1)
        // 32-bit counters wrap; unsigned subtraction handles one wrap per interval.
        let speed = Speed(down: Double(now.down &- last.down) / seconds, up: Double(now.up &- last.up) / seconds)
        let rate = max(speed.down, speed.up)
        if rate >= Self.startRate { fastSeconds += 1 } else { fastSeconds = 0 }
        if rate < Self.stopRate { slowSeconds += 1 } else { slowSeconds = 0 }
        if !isBusy, fastSeconds >= 2 {
            isBusy = true
        } else if isBusy, slowSeconds >= 3 {
            isBusy = false
            onChange?(nil)
        }
        if isBusy { onChange?(speed) }
    }

    /// Summed byte counters of the physical interfaces (en0, en1, …), so VPN
    /// tunnels don't count traffic twice.
    private static func counters() -> (down: UInt32, up: UInt32, time: Date) {
        var down: UInt32 = 0, up: UInt32 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0, Date()) }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.ifa_name).hasPrefix("en"),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            down &+= data.pointee.ifi_ibytes
            up &+= data.pointee.ifi_obytes
        }
        return (down, up, Date())
    }

    /// "12.4 MB/s", "850 KB/s".
    static func format(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: bytesPerSecond >= 100_000_000 ? "%.0f MB/s" : "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        return String(format: "%.0f KB/s", bytesPerSecond / 1000)
    }
}
