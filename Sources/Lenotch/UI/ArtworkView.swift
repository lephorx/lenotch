import SwiftUI

/// Album art, falling back to the player's app icon, then a placeholder.
struct ArtworkView: View {
    let artwork: NSImage?
    let fallback: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
            } else if let fallback {
                Image(nsImage: fallback).resizable().aspectRatio(contentMode: .fit).padding(4)
            } else {
                Color.white.opacity(0.08)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
