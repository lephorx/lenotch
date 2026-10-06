import AppKit
import SwiftUI

extension View {
    /// Mouse dragging and wheel navigation for the day strip and month grid.
    func calendarNavigation(stepDistance: CGFloat, oneStepPerGesture: Bool = false,
                            move: @escaping (Int) -> Void) -> some View {
        modifier(CalendarNavigation(stepDistance: stepDistance,
                                    oneStepPerGesture: oneStepPerGesture, move: move))
    }
}

private struct CalendarNavigation: ViewModifier {
    let stepDistance: CGFloat
    let oneStepPerGesture: Bool
    let move: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .background(CalendarWheelNavigation(stepDistance: stepDistance,
                                                oneStepPerGesture: oneStepPerGesture, move: move))
            .highPriorityGesture(DragGesture(minimumDistance: 8).onEnded { gesture in
                let translation = gesture.translation
                let distance = abs(translation.width) >= abs(translation.height)
                    ? translation.width : translation.height
                guard abs(distance) >= stepDistance / 2 else { return }
                let steps = oneStepPerGesture ? 1 : max(1, Int((abs(distance) / stepDistance).rounded()))
                move(distance < 0 ? steps : -steps)
            })
    }
}

private struct CalendarWheelNavigation: NSViewRepresentable {
    let stepDistance: CGFloat
    let oneStepPerGesture: Bool
    let move: (Int) -> Void

    func makeNSView(context: Context) -> WheelView { WheelView() }

    func updateNSView(_ view: WheelView, context: Context) {
        view.stepDistance = stepDistance
        view.oneStepPerGesture = oneStepPerGesture
        view.move = move
    }

    static func dismantleNSView(_ view: WheelView, coordinator: ()) { view.stop() }

    final class WheelView: NSView {
        var stepDistance: CGFloat = 36
        var oneStepPerGesture = false
        var move: ((Int) -> Void)?
        private var monitor: Any?
        private var travel: CGFloat = 0
        private var handledGesture = false
        private var lastScroll = Date.distantPast

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor,
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.scroll(event)
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            travel = 0
            handledGesture = false
        }

        private func scroll(_ event: NSEvent) {
            // Ignore inertia so a flick doesn't skip additional months or days.
            guard event.momentumPhase.isEmpty else { return }
            let now = Date()
            if event.phase.contains(.began) || now.timeIntervalSince(lastScroll) > 0.2 {
                travel = 0
                handledGesture = false
            }
            lastScroll = now
            guard !oneStepPerGesture || !handledGesture else { return }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            guard delta != 0 else { return }
            if !event.hasPreciseScrollingDeltas {
                // A regular mouse wheel navigates one item per wheel event.
                move?(delta < 0 ? 1 : -1)
                return
            }
            travel += delta
            guard abs(travel) >= stepDistance else { return }
            let steps = oneStepPerGesture ? 1 : Int(abs(travel) / stepDistance)
            let direction = travel < 0 ? 1 : -1
            travel += CGFloat(direction * steps) * stepDistance
            handledGesture = true
            move?(direction * steps)
        }
    }
}
