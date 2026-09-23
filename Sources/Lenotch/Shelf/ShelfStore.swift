import AppKit
import Observation

/// Files dropped on the notch. Holds references to the originals, not copies.
@Observable
final class ShelfStore {
    private(set) var items: [URL] = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "shelfItems"

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        if settings.keepShelfItems {
            items = (defaults.stringArray(forKey: Self.key) ?? [])
                .map(URL.init(fileURLWithPath:))
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    func add(_ urls: [URL]) {
        let new = urls.filter { url in !items.contains(url) }
        guard !new.isEmpty else { return }
        items.append(contentsOf: new)
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    func removeAll() {
        items.removeAll()
        persist()
    }

    /// Called when the "keep after restart" setting changes.
    func persist() {
        defaults.set(settings.keepShelfItems ? items.map(\.path) : [], forKey: Self.key)
    }

    // MARK: - Actions

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    /// Lets the user pick files in an open panel, then sends them via AirDrop.
    func chooseFilesForAirDrop() {
        let panel = NSOpenPanel()
        panel.title = "AirDrop"
        panel.prompt = "AirDrop"
        panel.message = "Choose files to send with AirDrop"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            self?.airDrop(panel.urls)
        }
    }

    /// Reads file URLs from drop providers and hands them back on the main thread.
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
