import AppKit
import SwiftUI

enum NotchState: Equatable {
    case closed
    case hovered
    case open
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case calendar
    case shelf
    case settings

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "music.note"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
    var title: String {
        switch self {
        case .home: return "Now Playing"
        case .calendar: return "Calendar"
        case .shelf: return "Shelf"
        case .settings: return "Settings"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .closed
    @Published var tab: NotchTab = .home
    @Published var geometry: NotchGeometry
    @Published var isDropTargeted = false

    let media = MediaController()
    let battery = BatteryMonitor()
    let calendar = CalendarService()
    let shelf = ShelfStore()
    let hud = SystemHUDController()
    let settings = Settings.shared

    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    // MARK: - Size for the current state

    /// Extra width the collapsed pill needs to show something either side of the cutout.
    /// The hardware notch is exactly as wide as the hardware notch, so anything we want to
    /// display while closed has to make the pill grow past it.
    private var closedSideInset: CGFloat {
        if hud.current != nil { return 150 }
        if media.isRunning && !media.nowPlaying.isEmpty { return 118 }
        if battery.hasBattery && settings.showBatteryPercent { return 74 }
        return 0
    }

    var contentSize: CGSize {
        switch state {
        case .closed:
            return CGSize(width: geometry.closedSize.width + closedSideInset,
                          height: geometry.closedSize.height)
        case .hovered:
            // A small swell under the cursor: the notch "notices" you before it opens.
            return CGSize(width: geometry.closedSize.width + max(closedSideInset, 26) + 18,
                          height: geometry.closedSize.height + 6)
        case .open:
            return geometry.openSize
        }
    }

    var isOpen: Bool { state == .open }

    var cornerRadius: CGFloat {
        state == .open ? Theme.cornerRadius : Theme.closedCornerRadius
    }

    // MARK: - Transitions

    func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        closeTask?.cancel()

        if inside {
            guard state == .closed else { return }
            withAnimation(Theme.content) { state = .hovered }
            guard settings.openOnHover else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(settings.hoverDelay * 1_000_000_000))
                guard !Task.isCancelled, state == .hovered else { return }
                open()
            }
        } else {
            guard state != .closed else { return }
            // A short grace period keeps the panel from snapping shut when the cursor
            // crosses the concave shoulders of the notch shape.
            closeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                close()
            }
        }
    }

    func open() {
        guard state != .open else { return }
        hoverTask?.cancel()
        closeTask?.cancel()
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        calendar.reload()
        withAnimation(Theme.open) { state = .open }
    }

    func close() {
        guard state != .closed else { return }
        hoverTask?.cancel()
        closeTask?.cancel()
        withAnimation(Theme.close) { state = .closed }
    }

    func toggle() {
        state == .open ? close() : open()
    }

    func select(_ tab: NotchTab) {
        guard self.tab != tab else { return }
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(Theme.content) { self.tab = tab }
    }

    func updateGeometry(_ new: NotchGeometry) {
        guard new != geometry else { return }
        geometry = new
    }

    // MARK: - Drops

    /// `shelf` is a `let`, so SwiftUI can't project a binding into it directly.
    var dropTargetBinding: Binding<Bool> {
        Binding(get: { self.shelf.isTargeted },
                set: { self.shelf.isTargeted = $0 })
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        // Opening on drop-in means you can drag a file at the notch and watch the shelf
        // unfold underneath it, which is the whole point of the gesture.
        select(.shelf)
        open()

        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, !urls.isEmpty else { return }
            self.shelf.add(urls: urls)
        }
        return true
    }
}
