import AppKit
import SwiftUI
import Observation

enum NotchTab: Hashable {
    case nowPlaying, shelf
}

@Observable
final class NotchViewModel {
    enum State { case closed, open }

    var state: State = .closed
    var selectedTab: NotchTab = .nowPlaying
    var geometry: NotchGeometry
    /// Set while the user drags the progress bar so the notch does not close mid-scrub.
    var isInteracting = false
    let media: NowPlayingService
    let settings: AppSettings
    let battery: BatteryMonitor
    let shelf: ShelfStore
    let visualizer: AudioVisualizer
    let camera = CameraMirror()
    /// The camera popup beside the notch; closes with the notch or on a second click.
    var isMirrorVisible = false
    let openSettings: () -> Void

    init(geometry: NotchGeometry, media: NowPlayingService, settings: AppSettings,
         battery: BatteryMonitor, shelf: ShelfStore, visualizer: AudioVisualizer,
         openSettings: @escaping () -> Void) {
        self.geometry = geometry
        self.media = media
        self.settings = settings
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

    /// Colour transition for the current style, with the song colour applied if enabled.
    var backgroundGradient: NotchGradient {
        settings.gradient(for: settings.appearance).resolved(musicColor: accentColor)
    }

    func toggleMirror() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isMirrorVisible.toggle() }
        // Driven by the toggle, not the popup's appear/disappear, which fire after the
        // animations and could stop the camera of a popup that was quickly reopened.
        if isMirrorVisible {
            camera.start()
        } else {
            camera.stop()
        }
    }

    /// Tabs turned on in Settings, in display order.
    var tabs: [NotchTab] {
        [.nowPlaying] + (settings.shelfEnabled ? [.shelf] : [])
    }

    /// The tab actually shown, falling back when the selected one is turned off.
    var visibleTab: NotchTab { tabs.contains(selectedTab) ? selectedTab : .nowPlaying }

    /// Whether the last tab change moved right (for the slide direction).
    private(set) var tabMovesForward = true

    /// Switches tabs with a slide in the matching direction.
    func select(_ tab: NotchTab) {
        guard tab != visibleTab, let from = tabs.firstIndex(of: visibleTab),
              let to = tabs.firstIndex(of: tab) else { return }
        // Set the direction first so the outgoing tab slides the right way too.
        tabMovesForward = to > from
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { self.selectedTab = tab }
        }
    }

    /// Moves to the next (+1) or previous (-1) tab; used by swipes.
    func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(of: visibleTab) else { return }
        let target = index + offset
        guard tabs.indices.contains(target) else { return }
        select(tabs[target])
    }

    var currentSize: CGSize {
        switch state {
        case .open: geometry.openSize
        case .closed: showsLiveActivity ? geometry.liveSize : geometry.closedSize
        }
    }
}
