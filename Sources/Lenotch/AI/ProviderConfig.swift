import AppKit
import CryptoKit
import Foundation

/// A usage provider defined in a JSON file, so providers (and their logos) can be
/// written by hand, shared and imported. See docs/provider-config.md.
///
/// ```json
/// {
///   "name": "OpenRouter",
///   "url": "https://openrouter.ai/api/v1/auth/key",
///   "apiKeyFile": "~/.config/openrouter/key",
///   "mode": "usedAndLimit",
///   "value": "data.usage",
///   "limit": "data.limit",
///   "label": "Credits",
///   "logo": "openrouter.png"
/// }
/// ```
struct ProviderConfig: Codable {
    var name: String
    var url: String
    var authHeader: String?
    var authPrefix: String?
    var apiKeyFile: String?
    /// `percent`, `usedAndLimit` or `remainingAndLimit`.
    var mode: String?
    var value: String
    var limit: String?
    var reset: String?
    var label: String?
    var symbol: String?
    /// A file next to the config, an absolute path, or a `data:image/…;base64,…` URL.
    var logo: String?
    var tintLogo: Bool?

    init(_ provider: CustomAIProvider, embeddingLogo: Bool) {
        name = provider.name
        url = provider.url
        authHeader = provider.authHeader
        authPrefix = provider.authPrefix
        apiKeyFile = provider.apiKeyFile
        mode = provider.mode.rawValue
        value = provider.valuePath
        limit = provider.limitPath.isEmpty ? nil : provider.limitPath
        reset = provider.resetPath.isEmpty ? nil : provider.resetPath
        label = provider.label
        symbol = provider.symbol
        tintLogo = provider.tintLogo
        if embeddingLogo, let url = provider.logoURL, let data = try? Data(contentsOf: url) {
            let type = url.pathExtension.lowercased() == "svg" ? "svg+xml" : url.pathExtension.lowercased()
            logo = "data:image/\(type);base64,\(data.base64EncodedString())"
        }
    }

    /// A custom provider for this config; `file` names the config in the Providers folder.
    func provider(file: String) -> CustomAIProvider {
        var provider = CustomAIProvider()
        provider.id = ProviderConfigStore.stableID(for: file)
        provider.name = name
        provider.url = url
        provider.authHeader = authHeader ?? "Authorization"
        provider.authPrefix = authPrefix ?? "Bearer "
        provider.apiKeyFile = apiKeyFile
        provider.mode = mode.flatMap(CustomAIProvider.Mode.init) ?? .percent
        provider.valuePath = value
        provider.limitPath = limit ?? ""
        provider.resetPath = reset ?? ""
        provider.label = label ?? "Usage"
        provider.symbol = symbol ?? "sparkles"
        provider.tintLogo = tintLogo
        provider.logoPath = ProviderConfigStore.resolveLogo(logo, configFile: file)
        provider.configFile = file
        return provider
    }
}

enum ProviderConfigStore {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lenotch", isDirectory: true)
    /// Drop `*.json` provider configs here.
    static let providersFolder = root.appendingPathComponent("Providers", isDirectory: true)
    /// Logos chosen in Settings (and ones embedded in configs) are kept here.
    static let logosFolder = root.appendingPathComponent("Logos", isDirectory: true)

    static func ensureFolders() {
        try? FileManager.default.createDirectory(at: providersFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logosFolder, withIntermediateDirectories: true)
    }

    /// Every valid config in the Providers folder, sorted by file name.
    static func loadAll() -> [CustomAIProvider] {
        ensureFolders()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: providersFolder.path)) ?? []
        return files.filter { $0.lowercased().hasSuffix(".json") }.sorted().compactMap { file in
            let url = providersFolder.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(ProviderConfig.self, from: data) else {
                NSLog("Lenotch: skipped invalid provider config \(file)")
                return nil
            }
            return config.provider(file: file)
        }
    }

    /// Copies a config (and a logo it references by file name) into the Providers folder.
    @discardableResult
    static func importConfig(from url: URL) throws -> String {
        ensureFolders()
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(ProviderConfig.self, from: data)
        var name = url.lastPathComponent
        if FileManager.default.fileExists(atPath: providersFolder.appendingPathComponent(name).path) {
            name = url.deletingPathExtension().lastPathComponent + "-\(Int(Date().timeIntervalSince1970)).json"
        }
        try data.write(to: providersFolder.appendingPathComponent(name))
        if let logo = config.logo, !logo.hasPrefix("data:"), !logo.hasPrefix("/"), !logo.hasPrefix("~") {
            let source = url.deletingLastPathComponent().appendingPathComponent(logo)
            let target = providersFolder.appendingPathComponent(logo)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: source, to: target)
            }
        }
        return name
    }

    /// Writes a provider as a shareable config with its logo embedded (never the API key).
    static func export(_ provider: CustomAIProvider, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(ProviderConfig(provider, embeddingLogo: true)).write(to: url)
    }

    /// Copies a chosen logo into the Logos folder; returns its file name.
    static func storeLogo(from url: URL) throws -> String {
        ensureFolders()
        let name = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased())"
        try FileManager.default.copyItem(at: url, to: logosFolder.appendingPathComponent(name))
        return name
    }

    /// Where a config's logo lives: next to the config, at a path, or decoded from a data URL.
    static func resolveLogo(_ logo: String?, configFile: String) -> String? {
        guard let logo, !logo.isEmpty else { return nil }
        if logo.hasPrefix("data:"), let comma = logo.firstIndex(of: ","),
           let data = Data(base64Encoded: String(logo[logo.index(after: comma)...])) {
            let type = logo.contains("svg") ? "svg" : logo.contains("jpeg") || logo.contains("jpg") ? "jpg" : "png"
            let url = logosFolder.appendingPathComponent("config-\(stableID(for: configFile).uuidString).\(type)")
            ensureFolders()
            if !FileManager.default.fileExists(atPath: url.path) { try? data.write(to: url) }
            return url.path
        }
        if logo.hasPrefix("/") || logo.hasPrefix("~") { return logo }
        return providersFolder.appendingPathComponent(logo).path
    }

    /// The same config file always gets the same id, so its order and on/off state stick.
    static func stableID(for file: String) -> UUID {
        let digest = Insecure.MD5.hash(data: Data(file.utf8))
        let bytes = Array(digest)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
