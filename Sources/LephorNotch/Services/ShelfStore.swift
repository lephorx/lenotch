import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let icon: NSImage
    let name: String
    let size: Int64
    let addedAt: Date

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.id == rhs.id }
}

/// The drop tray. Files are held by reference and by security-scoped bookmark so the shelf
/// survives relaunches and the originals are never copied or moved.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published var isTargeted = false

    private let defaultsKey = "shelfBookmarks"

    init() { restore() }

    func add(urls: [URL]) {
        var added = false
        for url in urls where !items.contains(where: { $0.url == url }) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            let size = Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
            let item = ShelfItem(url: url,
                                 icon: NSWorkspace.shared.icon(forFile: url.path),
                                 name: url.lastPathComponent,
                                 size: size,
                                 addedAt: Date())
            items.insert(item, at: 0)
            added = true
        }
        if added {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            persist()
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func quickLook(_ item: ShelfItem) {
        // Quick Look via the shared panel needs a key window; `qlmanage -p` is the reliable
        // path for an accessory-policy app that never takes focus.
        let task = Process()
        task.launchPath = "/usr/bin/qlmanage"
        task.arguments = ["-p", item.url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Everything on the shelf as one drag payload, so the whole tray can be thrown into
    /// Mail or Finder in a single gesture.
    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
    }

    // MARK: - Persistence

    private func persist() {
        let bookmarks: [Data] = items.compactMap {
            try? $0.url.bookmarkData(options: .withSecurityScope,
                                     includingResourceValuesForKeys: nil,
                                     relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: defaultsKey)
    }

    private func restore() {
        guard let bookmarks = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] else { return }
        var urls: [URL] = []
        for data in bookmarks {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data,
                                     options: .withSecurityScope,
                                     relativeTo: nil,
                                     bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }
            urls.append(url)
        }
        // `add` inserts at the front, so feed it reversed to preserve the saved order.
        add(urls: urls.reversed())
    }
}
