import SwiftUI

/// Grid of selectable audio sources.
struct SourcePicker: View {
    @Binding var selection: AudioSource

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(AudioSource.allCases) { source in
                SelectableCard(isSelected: selection == source) {
                    selection = source
                } label: {
                    HStack(spacing: 12) {
                        SourceIcon(source: source)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(.system(size: 13, weight: .semibold))
                            Text(source.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
            }
        }
    }
}

private struct SourceIcon: View {
    let source: AudioSource

    var body: some View {
        if let icon = source.appIcon {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.gradient)
                .overlay {
                    Image(systemName: source.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(2)
        }
    }

    private var tint: Color {
        switch source {
        case .nowPlaying: .gray
        case .spotify: .green
        case .appleMusic: .pink
        case .youtubeMusic: .red
        }
    }
}

/// Rounded card with an accent outline when selected.
struct SelectableCard<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.08 : 0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                  lineWidth: isSelected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}
