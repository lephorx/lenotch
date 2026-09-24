import AppKit
import Security
import SwiftUI

/// Built-in coding assistants whose usage limits the notch can show. Each is read
/// with the sign-in its own tool already keeps on this Mac; Lenotch never asks for a login.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case claude, codex, cursor, copilot, grok, kimi, opencode, amp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .copilot: "Copilot"
        case .grok: "Grok"
        case .kimi: "Kimi Code"
        case .opencode: "OpenCode"
        case .amp: "Amp"
        }
    }

    /// Where the sign-in comes from, for Settings.
    var source: String {
        switch self {
        case .claude: "Claude Code's sign-in (keychain)"
        case .codex: "~/.codex/auth.json"
        case .cursor: "Cursor editor's sign-in"
        case .copilot: "GitHub CLI (gh auth)"
        case .grok: "~/.grok/auth.json (Grok CLI)"
        case .kimi: "~/.kimi-code (Kimi Code CLI)"
        case .opencode: "~/.local/share/opencode/auth.json"
        case .amp: "~/.local/share/amp/secrets.json"
        }
    }

    var glyph: ProviderGlyph {
        switch self {
        case .claude: .outline(GlyphOutline.claude)
        case .codex: .outline(GlyphOutline.openai)
        case .cursor: .outline(GlyphOutline.cursor)
        case .copilot: .outline(GlyphOutline.copilot)
        case .grok: .outline(GlyphOutline.grok)
        case .kimi: .outline(GlyphOutline.kimi)
        case .opencode: .outline(GlyphOutline.opencode)
        case .amp: .image("glyph-amp")
        }
    }
}

/// How a provider's mark is drawn inside its ring.
enum ProviderGlyph {
    case outline([[CGPoint]])
    /// SVG in the app bundle's resources.
    case image(String)
    case symbol(String)
}

/// A user-defined usage source: any HTTP endpoint that returns JSON.
struct CustomAIProvider: Codable, Equatable, Identifiable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// The response holds a used percentage (0–100).
        case percent
        /// The response holds used and limit numbers.
        case usedAndLimit
        /// The response holds remaining and limit numbers.
        case remainingAndLimit

        var id: String { rawValue }
        var title: String {
            switch self {
            case .percent: "Used %"
            case .usedAndLimit: "Used / limit"
            case .remainingAndLimit: "Remaining / limit"
            }
        }
    }

    var id = UUID()
    var name = "My Provider"
    var symbol = "sparkles"
    var color = RGBAColor(red: 0.39, green: 0.4, blue: 0.95, alpha: 1)
    var url = ""
    var authHeader = "Authorization"
    var authPrefix = "Bearer "
    var mode = Mode.percent
    /// Dot paths into the JSON, e.g. `data.usage.percent` or `limits.0.used`.
    var valuePath = ""
    var limitPath = ""
    /// Optional: when the limit resets (ISO 8601 date or Unix seconds).
    var resetPath = ""
    var label = "Usage"

    var key: String { "custom:\(id.uuidString)" }

    // MARK: API key (kept in the keychain, never in preferences)

    private static let keychainService = "com.lephorx.Lenotch.custom-provider"

    var apiKey: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: Self.keychainService,
            kSecAttrAccount: id.uuidString, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveAPIKey(_ key: String) {
        let base: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: Self.keychainService,
                                     kSecAttrAccount: id.uuidString]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    func deleteAPIKey() { saveAPIKey("") }
}

/// A row in the usage widget: a built-in provider or a custom one.
struct UsageSource: Identifiable, Equatable {
    let id: String
    let title: String
    let glyph: ProviderGlyph
    let custom: CustomAIProvider?

    static func == (lhs: UsageSource, rhs: UsageSource) -> Bool { lhs.id == rhs.id && lhs.custom == rhs.custom }

    init(_ provider: AIProvider) {
        id = provider.rawValue
        title = provider.title
        glyph = provider.glyph
        custom = nil
    }

    init(_ provider: CustomAIProvider) {
        id = provider.key
        title = provider.name
        glyph = .symbol(provider.symbol)
        custom = provider
    }

    /// Resolves a saved key ("claude", "custom:<uuid>") against the custom providers.
    static func resolve(_ key: String, customs: [CustomAIProvider]) -> UsageSource? {
        if let provider = AIProvider(rawValue: key) { return UsageSource(provider) }
        return customs.first { $0.key == key }.map(UsageSource.init)
    }
}

/// Draws a provider's mark at a given size, in the current foreground colour.
struct ProviderGlyphView: View {
    let glyph: ProviderGlyph
    var size: CGFloat = 20

    var body: some View {
        switch glyph {
        case .outline(let outline):
            GlyphShape(outline: outline)
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
        case .image(let name):
            if let image = Self.image(named: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8, weight: .semibold))
                .frame(width: size, height: size)
        }
    }

    private static var cache: [String: NSImage] = [:]

    private static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let url = Bundle.main.url(forResource: name, withExtension: "svg")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/\(name).svg")
        let image = NSImage(contentsOf: url)
        image?.isTemplate = true
        cache[name] = image
        return image
    }
}
