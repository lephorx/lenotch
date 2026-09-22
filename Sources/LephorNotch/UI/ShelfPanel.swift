import SwiftUI
import UniformTypeIdentifiers

struct ShelfPanel: View {
    @ObservedObject var shelf: ShelfStore

    private let columns = [GridItem(.adaptive(minimum: 78, maximum: 100), spacing: 10)]

    var body: some View {
        VStack(spacing: 8) {
            header
            if shelf.items.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(shelf.items) { item in
                            ShelfTile(item: item, shelf: shelf)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Shelf")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text(shelf.items.isEmpty ? "" : "\(shelf.items.count)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(.white.opacity(0.85)))
                .opacity(shelf.items.isEmpty ? 0 : 1)
            Spacer()
            if !shelf.items.isEmpty {
                Button("Clear") { withAnimation(Theme.content) { shelf.clear() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(.white.opacity(shelf.isTargeted ? 0.9 : 0.3))
                .scaleEffect(shelf.isTargeted ? 1.15 : 1)
            Text(shelf.isTargeted ? "Drop to add" : "Drag files onto the notch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(shelf.isTargeted ? .white : Theme.secondaryText)
            Text("They stay here until you drag them back out.")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.white.opacity(shelf.isTargeted ? 0.45 : 0.14)))
        .animation(Theme.content, value: shelf.isTargeted)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            Text(item.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24, alignment: .top)

            Text(item.sizeText)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.32))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(hovering ? 0.12 : 0.05)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(Theme.content) { shelf.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.content, value: hovering)
        .onDrag { shelf.dragProvider(for: item) } preview: {
            Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
        }
        .onTapGesture(count: 2) { shelf.open(item) }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Quick Look") { shelf.quickLook(item) }
            Button("Reveal in Finder") { shelf.reveal(item) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
    }
}
