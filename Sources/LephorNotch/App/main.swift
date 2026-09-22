import AppKit

// Top-level code runs outside the main actor, but everything AppKit touches lives on it.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Held for the process lifetime; NSApplication only keeps a weak delegate reference.
    objc_setAssociatedObject(app, "lephor.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
