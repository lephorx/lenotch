import AppKit
import WebKit

/// Signs in to the DeepSeek Platform in Lenotch's own window, the way codenotch does.
/// The page runs in a private web view (nothing is read from Safari or Chrome, and nothing
/// stays on disk); once the user has signed in, the Platform's session token is taken
/// from the page, checked once and kept in the keychain.
@MainActor
final class DeepSeekSignIn: NSObject, NSWindowDelegate {
    static let shared = DeepSeekSignIn()

    private var window: NSWindow?
    private var webView: WKWebView?
    private var poll: Task<Void, Never>?
    private var completion: ((Bool) -> Void)?

    /// Opens the sign-in window; `completion` gets whether an account was signed in.
    func present(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760), configuration: configuration)
        let window = EditingWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                                   backing: .buffered, defer: false)
        window.title = "Sign in to DeepSeek"
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: DeepSeekUsage.platform))
        self.window = window
        self.webView = webView
        startPolling()
    }

    /// Looks for the session token the Platform keeps in the page's local storage once
    /// signed in. Reading it is local; only a token that turns up is checked with DeepSeek.
    private func startPolling() {
        poll = Task { [weak self] in
            var checked: String?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let webView = self.webView, !webView.isLoading,
                      webView.url?.host == DeepSeekUsage.platform.host,
                      let token = await self.pageToken(webView), token != checked else { continue }
                checked = token
                guard (try? await DeepSeekUsage.fetchAccount(token: token)) != nil else { continue }
                DeepSeekUsage.saveSessionToken(token)
                self.finish(signedIn: true)
                return
            }
        }
    }

    private func pageToken(_ webView: WKWebView) async -> String? {
        let script = """
        const raw = localStorage.getItem('userToken');
        if (!raw) return null;
        const pick = (value) => {
            if (typeof value === 'string') return value.trim() || null;
            if (!value || typeof value !== 'object') return null;
            for (const key of ['value', 'token', 'access_token', 'accessToken']) {
                const found = pick(value[key]);
                if (found) return found;
            }
            return null;
        };
        try { return pick(JSON.parse(raw)); } catch (_) { return raw.trim() || null; }
        """
        let result = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
        guard let token = result as? String, !token.isEmpty else { return nil }
        return token.hasPrefix("Bearer ") ? String(token.dropFirst(7)) : token
    }

    private func finish(signedIn: Bool) {
        poll?.cancel()
        poll = nil
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil
        completion?(signedIn)
        completion = nil
    }

    func windowWillClose(_ notification: Notification) {
        finish(signedIn: false)
    }
}

/// Lenotch has no Edit menu, so ⌘C, ⌘V and friends are routed here; without this
/// a password or code couldn't be pasted into the sign-in page.
private final class EditingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let action: Selector? = switch (flags, event.charactersIgnoringModifiers) {
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"), ([.command, .shift], "Z"): Selector(("redo:"))
        case (.command, "w"): #selector(NSWindow.performClose(_:))
        default: nil
        }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
