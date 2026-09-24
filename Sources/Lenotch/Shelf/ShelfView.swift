import SwiftUI
import UniformTypeIdentifiers

/// Files dropped on the notch, with an AirDrop target on the right.
struct ShelfView: View {
    let model: NotchViewModel
    let isDropTargeted: Bool

    private var shelf: ShelfStore { model.shelf }
    private var glass: Bool { model.settings.appearance == .glass }

    var body: some View {
        HStack(spacing: 12) {
            if model.settings.showFileShelf {
                dropZone
                    .contextMenu {
                        if !shelf.items.isEmpty {
                            Button("AirDrop All") { shelf.airDrop(shelf.items) }
                            Button("Show All in Finder") { shelf.revealInFinder(shelf.items) }
                            Divider()
                            Button("Clear Shelf") { shelf.removeAll() }
                        }
                    }
                    .slideIn(0)
            }

            if model.settings.showAirDrop {
                // Without the file shelf, AirDrop stretches across the tab.
                AirDropTarget(shelf: shelf, glass: glass, stretched: !model.settings.showFileShelf)
                    .slideIn(1)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    /// Glass card in glass mode, dashed outline otherwise.
    @ViewBuilder
    private var dropZone: some View {
        let content = Group {
            if shelf.items.isEmpty {
                emptyState
            } else {
                items
            }
        }
        if glass {
            GlassCard(isRaised: isDropTargeted) { content }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(isDropTargeted ? 0.5 : 0.15),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }

    private var emptyState: some View {
        VStack(spacing: glass ? 8 : 6) {
            Image(systemName: glass ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: glass ? 18 : 22, weight: .medium))
            Text("Drop files here")
                .font(.system(size: glass ? 14 : 12, weight: glass ? .semibold : .medium))
        }
        .foregroundStyle(.white.opacity(isDropTargeted ? 0.9 : glass ? 0.6 : 0.45))
    }

    private var items: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shelf.items, id: \.self) { url in
                    ShelfItemView(url: url, shelf: shelf)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct ShelfItemView: View {
    let url: URL
    let shelf: ShelfStore
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: url))
                .resizable()
                .frame(width: 42, height: 42)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(isHovered ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .contextMenu {
            Button("Open") { shelf.open(url) }
            Button("Show in Finder") { shelf.revealInFinder([url]) }
            Button("AirDrop") { shelf.airDrop([url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(url) }
        }
    }
}

/// Drop files here to send them via AirDrop; click to pick files to send.
private struct AirDropTarget: View {
    let shelf: ShelfStore
    let glass: Bool
    var stretched = false
    @State private var isTargeted = false
    @State private var isHovered = false

    private static let cornerRadius: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Button { shelf.chooseFilesForAirDrop() } label: {
            Group {
                if glass {
                    GlassCard(cornerRadius: Self.cornerRadius, isRaised: isTargeted || isHovered) { label }
                } else {
                    label
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(shape.fill(.white.opacity(isTargeted ? 0.14 : isHovered ? 0.09 : 0.06)))
                }
            }
            .frame(width: stretched ? nil : 104)
            .frame(maxWidth: stretched ? .infinity : nil)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            ShelfStore.loadURLs(from: providers) { shelf.airDrop($0) }
            return true
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    /// Grey share icon in a soft circle with the title underneath, in both styles.
    private var label: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(.white.opacity(isTargeted ? 0.22 : isHovered ? 0.16 : 0.1))
                .frame(width: 46, height: 46)
                .overlay {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .offset(y: -1)
                }
            Text("AirDrop")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}
