import Foundation
import IOKit.ps
import SwiftUI

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    @Published private(set) var timeRemaining: Int = -1
    @Published private(set) var isLowPowerMode = false

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?

    init() {
        refresh()
        // IOKit posts a notification whenever any power source changes; the timer is only a
        // safety net for the time-remaining estimate, which updates lazily.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        timer?.invalidate()
    }

    func refresh() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { hasBattery = false; return }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType
            else { continue }

            hasBattery = true
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            percentage = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
            isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            timeRemaining = info[key] as? Int ?? -1
            return
        }
        hasBattery = false
    }

    var timeRemainingText: String? {
        guard timeRemaining > 0 else { return nil }
        let hours = timeRemaining / 60
        let minutes = timeRemaining % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var tint: Color {
        if isCharging { return Color(red: 0.42, green: 0.86, blue: 0.45) }
        if percentage <= 10 { return Color(red: 0.98, green: 0.35, blue: 0.32) }
        if percentage <= 20 { return Color(red: 0.98, green: 0.72, blue: 0.24) }
        return .white
    }
}
