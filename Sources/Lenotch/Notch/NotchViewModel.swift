import AppKit
import AVFoundation
import EventKit
import SwiftUI
import Observation

/// The three fixed views in the open notch.
enum NotchPage: Int, CaseIterable, Identifiable {
    case player, shelf, aiUsage

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .player: "Now Playing"
        case .shelf: "Shelf"
        case .aiUsage: "AI Usage"
        }
    }
    var icon: String {
        switch self {
        case .player: "logo"
        case .shelf: "tray.fill"
        case .aiUsage: "sparkles"
        }
    }
}

@Observable
final class NotchViewModel {
    enum State { case closed, open }

    var state: State = .closed
    /// The first-launch intro is playing (the notch ignores the pointer meanwhile).
    var isShowingIntro = false
    /// A fresh identity resets IntroView's animation state on every replay.
    var introGeneration = UUID()
    /// Keeps the chosen appearance visible while the setup opacity slider is adjusted.
    var isShowingAppearancePreview = false
    /// Briefly showing the current song under the closed notch.
    var isPeeking = false
    /// A volume or brightness change showing beside the closed notch.
    var indicator: SystemIndicator?
    /// The crypto ticker fills the closed notch while nothing else shows there.
    var showsCrypto: Bool { settings.showCrypto && !crypto.prices.isEmpty }
    /// Apps using the microphone or camera right now.
    var privacy = PrivacyActivity()
    /// The notch gets an orange/green outline (Lenotch's own camera mirror doesn't count).
    var showsPrivacy: Bool {
        settings.showPrivacyIndicator && (privacy.isMicOn || (privacy.isCameraOn && !isMirrorVisible))
    }
    var selectedPage: NotchPage = .player
    var geometry: NotchGeometry
    /// Set while the user drags the progress bar so the notch does not close mid-scrub.
    var isInteracting = false
    let media: NowPlayingService
    let settings: AppSettings
    let battery: BatteryMonitor
    let shelf: ShelfStore
    let visualizer: AudioVisualizer
    let camera = CameraMirror()
    let calendar: CalendarService
    let weather: WeatherService
    let crypto: CryptoService
    let aiUsage = AIUsageService()
    /// The AI usage ring under the pointer, for the bubble below the notch.
    private(set) var usageHover: UsageHover?
    @ObservationIgnored var onUsageHoverChange: (() -> Void)?

    func setUsageHover(_ hover: UsageHover?) {
        guard hover != usageHover else { return }
        usageHover = hover
        onUsageHoverChange?()
    }
    /// Pointer is over a sideways-scrolling area (the calendar's day strip), where
    /// two-finger swipes scroll instead of switching tabs.
    var isOverHorizontalScroller = false
    /// Pointer is over a vertically scrolling list (the calendar's events), where
    /// swiping up scrolls instead of closing the notch.
    var isOverVerticalScroller = false
    /// The camera popup beside the notch; closes with the notch or on a second click.
    var isMirrorVisible = false
    let openSettings: () -> Void

    init(geometry: NotchGeometry, media: NowPlayingService, settings: AppSettings,
         battery: BatteryMonitor, shelf: ShelfStore, visualizer: AudioVisualizer,
         openSettings: @escaping () -> Void) {
        self.geometry = geometry
        self.media = media
        self.settings = settings
        self.calendar = CalendarService(settings: settings)
        self.weather = WeatherService(settings: settings)
        self.crypto = CryptoService(settings: settings)
        self.battery = battery
        self.shelf = shelf
        self.visualizer = visualizer
        self.openSettings = openSettings
    }

    var showsLiveActivity: Bool { media.track != nil && media.isPlaying }

    /// Real audio levels for the equalizer, when that's turned on.
    var equalizerSource: AudioVisualizer? { settings.realAudioVisualizer ? visualizer : nil }

    /// Colour taken from the album art, if tinting is available.
    var accentColor: Color? { media.accentColor.map(Color.init(nsColor:)) }
    var equalizerColor: Color { settings.tintEqualizer ? accentColor ?? .white : .white }
    /// `nil` means the default (white) progress fill.
    var progressColor: Color? { settings.tintProgressBar ? accentColor : nil }

    /// Colour transition for the current style. Music colour is drawn as a
    /// local glow in the background instead of tinting the whole lower edge.
    var backgroundGradient: NotchGradient {
        settings.gradient(for: settings.appearance)
    }

    func toggleMirror() {
        onOpenSizeChange?()
        // No bounce: the popup hangs from the top of the screen, and overshooting
        // would pull it down far enough to show the gap above it.
        withAnimation(.smooth(duration: 0.35)) { isMirrorVisible.toggle() }
        // Driven by the toggle, not the popup's appear/disappear, which fire after the
        // animations and could stop the camera of a popup that was quickly reopened.
        if isMirrorVisible {
            camera.start()
        } else {
            camera.stop()
        }
    }

    // MARK: - Pages

    /// Tabs shown in the notch; AI Usage only once it's switched on in Settings.
    var pages: [NotchPage] {
        NotchPage.allCases.filter { page in
            switch page {
            case .player: true
            case .shelf: settings.showsShelfTab
            case .aiUsage: settings.aiUsageEnabled
            }
        }
    }

    /// The selected tab, falling back to the player when it's been switched off.
    var visiblePage: NotchPage { pages.contains(selectedPage) ? selectedPage : .player }

    // Features that need a permission stay out of the notch until it's allowed.
    var isCalendarAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    /// Calendar beside the music: switched on in Settings and allowed.
    var showsCalendar: Bool { settings.showCalendar && isCalendarAllowed }
    var isCameraAllowed: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    var openWidth: CGFloat { openSize(for: visiblePage).width }

    /// Each tab is only as big as what it shows.
    func openSize(for page: NotchPage) -> CGSize {
        switch page {
        case .player:
            switch (settings.showMusic, showsCalendar) {
            case (true, true): return geometry.openSize
            case (true, false): return geometry.openSize(contentWidth: 460, bodyHeight: 166)
            // The calendar alone stretches across a mid-sized tab.
            case (false, true):
                // The month grid needs the taller tab; the day strip keeps the usual height.
                return settings.expandedCalendarStyle == .month
                    ? geometry.openSize(contentWidth: 600, bodyHeight: NotchGeometry.maxBodyHeight)
                    : geometry.openSize(contentWidth: 580, bodyHeight: 166)
            // Neither: logo, name, time and the weather.
            case (false, false): return geometry.openSize(contentWidth: 540, bodyHeight: 150)
            }
        case .shelf:
            // AirDrop alone is a smaller tab, stretched across it.
            return geometry.openSize(contentWidth: settings.showFileShelf ? 500 : 380, bodyHeight: 150)
        case .aiUsage:
            // Rings: 8 per row at most, two rows at most.
            let count = min(max(visibleUsageCount, 1), 16)
            let perRow = min(count, 8)
            let rowWidth = CGFloat(perRow) * 52 + CGFloat(perRow - 1) * 26
            return geometry.openSize(contentWidth: rowWidth + 60, bodyHeight: count > 8 ? 160 : 118)
        }
    }

    /// AI usage sources with something to show (tools that aren't set up are hidden).
    var visibleUsageCount: Int {
        settings.usageSources.filter { aiUsage.usage[$0.id] != .notSetUp }.count
    }

    /// Called when the open notch's size changes, so the camera popup can follow its edge.
    @ObservationIgnored var onOpenSizeChange: (() -> Void)?

    /// Whether the last page change moved right (for the slide direction).
    private(set) var pageMovesForward = true

    /// Switches pages with a slide in the matching direction.
    func select(_ page: NotchPage) {
        guard page != visiblePage else { return }
        // Set the direction first and switch on the next run-loop turn, so the
        // outgoing page already knows which way to leave.
        pageMovesForward = page.rawValue > visiblePage.rawValue
        DispatchQueue.main.async {
            // One spring for the content, the selection pill and the notch's resize.
            withAnimation(Self.pageSpring) { self.selectedPage = page }
            self.onOpenSizeChange?()
        }
    }

    static let pageSpring = Animation.spring(response: 0.46, dampingFraction: 0.86)

    /// Moves to the next (+1) or previous (-1) page; used by swipes.
    func selectPage(offset: Int) {
        guard let index = pages.firstIndex(of: visiblePage), pages.indices.contains(index + offset) else { return }
        select(pages[index + offset])
    }

    var currentSize: CGSize {
        if isShowingIntro || isShowingAppearancePreview { return geometry.introSize }
        if indicator != nil, state == .closed { return geometry.indicatorSize }
        if isPeeking, state == .closed { return geometry.peekSize }
        return switch state {
        case .open: openSize(for: visiblePage)
        case .closed:
            showsLiveActivity ? geometry.liveSize
                : showsCrypto ? geometry.indicatorSize : geometry.closedSize
        }
    }
}
