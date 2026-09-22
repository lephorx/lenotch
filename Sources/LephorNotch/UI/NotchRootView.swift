import SwiftUI
import UniformTypeIdentifiers

/// The whole notch, top-anchored inside an oversized transparent panel. The window never
/// resizes; only this view does, which is what keeps the open/close animation smooth.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var settings: Settings

    var body: some View {
        let size = model.contentSize
        let shape = NotchShape(topRadius: model.isOpen ? 12 : 7,
                               bottomRadius: model.cornerRadius)

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(shape: shape,
                                appearance: settings.appearance,
                                isOpen: model.isOpen,
                                tint: model.media.artworkColors,
                                blackBandHeight: model.geometry.notchSize.height)

                Group {
                    if model.isOpen {
                        ExpandedView(model: model, notchWidth: model.geometry.notchSize.width)
                            .transition(.opacity.animation(.easeOut(duration: 0.14).delay(0.06)))
                    } else {
                        ClosedContentView(model: model,
                                          media: model.media,
                                          hud: model.hud,
                                          battery: model.battery,
                                          size: size,
                                          notchWidth: model.geometry.notchSize.width)
                            .transition(.opacity.animation(.easeOut(duration: 0.10)))
                    }
                }
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(shape)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                // The drop target covers the whole pill, so files can be thrown at the
                // closed notch without opening it first.
                shape
                    .strokeBorder(Theme.accent.opacity(model.shelf.isTargeted ? 0.9 : 0), lineWidth: 2)
                    .animation(Theme.content, value: model.shelf.isTargeted)
            }
            .contentShape(shape)
            .onHover { model.hoverChanged($0) }
            .onTapGesture { model.toggle() }
            .onDrop(of: [.fileURL], isTargeted: model.dropTargetBinding) { providers in
                model.handleDrop(providers: providers)
            }
            .contextMenu {
                Button("Now Playing") { model.select(.home); model.open() }
                Button("Calendar") { model.select(.calendar); model.open() }
                Button("Shelf") { model.select(.shelf); model.open() }
                Divider()
                Button("Settings") { model.select(.settings); model.open() }
                Button("Quit LephorNotch") { NSApp.terminate(nil) }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.open, value: model.state)
        .animation(Theme.content, value: size)
        .colorScheme(.dark)
    }
}
