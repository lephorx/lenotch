import Foundation
import Observation
import SwiftUI

/// One usage limit window, e.g. the 5-hour session or the week.
struct UsageWindow: Identifiable, Equatable {
    let id: String
    let label: String
    /// 0...1
    let used: Double
    let resetsAt: Date?
}

enum ProviderUsage: Equatable {
    case loading
    case ok(plan: String?, windows: [UsageWindow])
    /// Signed in, but the reading failed or needs action (message says what).
    case problem(String)
    /// The tool isn't installed or signed in on this Mac; hidden in the notch.
    case notSetUp
}

/// Fetches usage for the enabled sources. Only polls while the widget is on screen.
@Observable
final class AIUsageService {
    /// Keyed by `UsageSource.id`.
    private(set) var usage: [String: ProviderUsage] = [:]
    @ObservationIgnored private var lastRefresh: [String: Date] = [:]
    /// Providers' usage endpoints are rate limited; don't ask more often than this.
    private static let minimumInterval: TimeInterval = 60

    func refresh(_ sources: [UsageSource], force: Bool = false) async {
        await withTaskGroup(of: (String, ProviderUsage?).self) { group in
            for source in sources {
                if !force, let last = lastRefresh[source.id], Date().timeIntervalSince(last) < Self.minimumInterval {
                    continue
                }
                lastRefresh[source.id] = Date()
                if usage[source.id] == nil { usage[source.id] = .loading }
                group.addTask { (source.id, await Self.fetch(source)) }
            }
            for await (id, result) in group {
                // nil means "keep the previous reading" (e.g. rate limited).
                if let result { usage[id] = result }
            }
        }
    }

    /// One reading, for the Test button in Settings.
    static func test(_ provider: CustomAIProvider) async -> ProviderUsage {
        await fetch(UsageSource(provider)) ?? .problem("Rate limited, try again shortly")
    }

    private static func fetch(_ source: UsageSource) async -> ProviderUsage? {
        do {
            if let custom = source.custom { return try await CustomUsage.fetch(custom) }
            switch AIProvider(rawValue: source.id) {
            case .claude: return try await ClaudeUsage.fetch()
            case .codex: return try await CodexUsage.fetch()
            case .cursor: return try await CursorUsage.fetch()
            case .copilot: return try await CopilotUsage.fetch()
            case .grok: return try await GrokUsage.fetch()
            case .kimi: return try await KimiUsage.fetch()
            case .opencode: return try await OpenCodeUsage.fetch()
            case .amp: return try await AmpUsage.fetch()
            case nil: return .notSetUp
            }
        } catch UsageError.notSetUp {
            return .notSetUp
        } catch UsageError.rateLimited {
            return nil
        } catch UsageError.problem(let message) {
            return .problem(message)
        } catch {
            return .problem("Couldn't reach \(source.title)")
        }
    }
}

enum UsageError: Error {
    case notSetUp
    case rateLimited
    case problem(String)
}

// MARK: - Shared helpers

enum UsageHTTP {
    static func get(_ url: URL, headers: [String: String], method: String = "GET", body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Lenotch", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        // Ephemeral: no cookie store or URL cache kept in memory between polls.
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401, 403: throw UsageError.problem("Sign in again")
        case 429: throw UsageError.rateLimited
        default: throw UsageError.problem("Usage unavailable right now")
        }
    }

    /// Runs a command-line tool and returns its standard output.
    static func run(_ path: String, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: process.terminationStatus == 0
                    ? String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil)
            }
            do { try process.run() } catch { continuation.resume(returning: nil) }
        }
    }

    static let isoDate: (String) -> Date? = { text in
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

// MARK: - Claude Code

/// Claude Code keeps its OAuth sign-in in the login keychain; `/usr/bin/security`
/// (which Claude Code itself uses) can read it without a keychain prompt.
/// Expired tokens aren't refreshed here, since that would sign Claude Code out.
enum ClaudeUsage {
    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double
        }
        let claudeAiOauth: OAuth
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let seven_day_sonnet: Window?
    }

    static func fetch() async throws -> ProviderUsage {
        guard let json = await UsageHTTP.run("/usr/bin/security",
                                             ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: Data(json.utf8)),
              !credentials.claudeAiOauth.accessToken.isEmpty else { throw UsageError.notSetUp }
        guard credentials.claudeAiOauth.expiresAt / 1000 > Date().timeIntervalSince1970 else {
            throw UsageError.problem("Open Claude Code to refresh")
        }

        let data = try await UsageHTTP.get(URL(string: "https://api.anthropic.com/api/oauth/usage")!, headers: [
            "Authorization": "Bearer \(credentials.claudeAiOauth.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
        ])
        let response = try JSONDecoder().decode(Response.self, from: data)
        let windows = [("session", "Current session", response.five_hour), ("week", "All models", response.seven_day),
                       ("opus", "Opus", response.seven_day_opus), ("sonnet", "Sonnet", response.seven_day_sonnet)]
            .compactMap { id, label, window -> UsageWindow? in
                guard let utilization = window?.utilization else { return nil }
                return UsageWindow(id: id, label: label, used: utilization / 100,
                                   resetsAt: window?.resets_at.flatMap(UsageHTTP.isoDate))
            }
        return .ok(plan: nil, windows: windows)
    }
}

// MARK: - Codex

/// Codex keeps its ChatGPT sign-in in ~/.codex/auth.json and refreshes it itself.
enum CodexUsage {
    private struct Auth: Decodable {
        struct Tokens: Decodable {
            let access_token: String
            let account_id: String
        }
        let tokens: Tokens?
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let used_percent: Double?
            let limit_window_seconds: Double?
            let reset_at: Double?
        }
        struct RateLimit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        let plan_type: String?
        let rate_limit: RateLimit?
    }

    static func fetch() async throws -> ProviderUsage {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let tokens = try? JSONDecoder().decode(Auth.self, from: data).tokens,
              !tokens.access_token.isEmpty else { throw UsageError.notSetUp }

        let body = try await UsageHTTP.get(URL(string: "https://chatgpt.com/backend-api/wham/usage")!, headers: [
            "Authorization": "Bearer \(tokens.access_token)",
            "ChatGPT-Account-Id": tokens.account_id,
        ])
        let response = try JSONDecoder().decode(Response.self, from: body)
        let windows = [("primary", response.rate_limit?.primary_window),
                       ("secondary", response.rate_limit?.secondary_window)]
            .compactMap { id, window -> UsageWindow? in
                guard let window, let used = window.used_percent else { return nil }
                return UsageWindow(id: id, label: label(forSeconds: window.limit_window_seconds, fallback: id),
                                   used: used / 100,
                                   resetsAt: window.reset_at.map(Date.init(timeIntervalSince1970:)))
            }
        return .ok(plan: response.plan_type?.capitalized, windows: windows)
    }

    private static func label(forSeconds seconds: Double?, fallback: String) -> String {
        switch seconds {
        case 18_000?: "5h limit"
        case 604_800?: "Weekly limit"
        case let seconds? where seconds >= 86_400: "\(Int(seconds / 86_400))-day limit"
        case let seconds?: "\(Int(seconds / 3_600))h limit"
        default: fallback == "primary" ? "5h limit" : "Weekly limit"
        }
    }
}

// MARK: - GitHub Copilot

/// Copilot's quota, authenticated with the GitHub CLI's sign-in.
enum CopilotUsage {
    private struct Response: Decodable {
        struct Quota: Decodable {
            let percent_remaining: Double?
            let unlimited: Bool?
        }
        let copilot_plan: String?
        let quota_reset_date: String?
        let quota_snapshots: [String: Quota]?
    }

    static func fetch() async throws -> ProviderUsage {
        let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let gh, let token = await UsageHTTP.run(gh, ["auth", "token"]), !token.isEmpty else {
            throw UsageError.notSetUp
        }
        let data = try await UsageHTTP.get(URL(string: "https://api.github.com/copilot_internal/user")!, headers: [
            "Authorization": "token \(token)",
            "Accept": "application/json",
        ])
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.copilot_plan != nil else { throw UsageError.notSetUp }

        let resetsAt = response.quota_reset_date.flatMap { text -> Date? in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }
        let windows = [("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions")]
            .compactMap { key, label -> UsageWindow? in
                guard let quota = response.quota_snapshots?[key], quota.unlimited != true,
                      let remaining = quota.percent_remaining else { return nil }
                return UsageWindow(id: key, label: label, used: 1 - remaining / 100, resetsAt: resetsAt)
            }
        return .ok(plan: response.copilot_plan?.capitalized, windows: windows)
    }
}

// MARK: - JSON helpers

enum JSONValue {
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func number(_ any: Any?) -> Double? {
        if let number = any as? NSNumber { return number.doubleValue }
        if let text = any as? String { return Double(text) }
        return nil
    }

    /// Reads a value by dot path, e.g. `data.limits.0.used`.
    static func value(at path: String, in root: Any) -> Any? {
        path.split(separator: ".").reduce(Optional(root)) { current, component in
            if let dictionary = current as? [String: Any] { return dictionary[String(component)] }
            if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
    }

    /// ISO 8601 text, or Unix seconds / milliseconds.
    static func date(_ any: Any?) -> Date? {
        if let text = any as? String {
            return UsageHTTP.isoDate(text) ?? Double(text).map(date(fromEpoch:))
        }
        return number(any).map(date(fromEpoch:))
    }

    private static func date(fromEpoch value: Double) -> Date {
        Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value)
    }
}

// MARK: - Cursor

/// The Cursor editor keeps its session in its SQLite state database.
enum CursorUsage {
    static func fetch() async throws -> ProviderUsage {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        guard FileManager.default.fileExists(atPath: path),
              let token = SQLiteReader.value(for: "cursorAuth/accessToken", inDatabase: path), !token.isEmpty
        else { throw UsageError.notSetUp }
        let account = SQLiteReader.value(for: "cursorAuth/stripeMembershipAuthId", inDatabase: path)
            .flatMap { $0.isEmpty ? nil : $0 } ?? JWT.claims(token)?["sub"] as? String
        guard let account else { throw UsageError.notSetUp }

        let data = try await UsageHTTP.get(URL(string: "https://cursor.com/api/usage-summary")!, headers: [
            "Cookie": "WorkosCursorSessionToken=\(account)::\(token)",
            "Accept": "application/json",
        ])
        guard let root = JSONValue.object(data) else { throw UsageError.problem("Unexpected response") }
        let resetsAt = JSONValue.date(root["billingCycleEnd"])
        let plan = (root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        if let auto = JSONValue.number(plan["autoPercentUsed"]) {
            windows.append(UsageWindow(id: "auto", label: "Auto usage", used: auto / 100, resetsAt: resetsAt))
        }
        if let api = JSONValue.number(plan["apiPercentUsed"]), api > 0 {
            windows.append(UsageWindow(id: "api", label: "API usage", used: api / 100, resetsAt: resetsAt))
        }
        if windows.isEmpty, let total = JSONValue.number(plan["totalPercentUsed"]) {
            windows.append(UsageWindow(id: "total", label: "Included usage", used: total / 100, resetsAt: resetsAt))
        }
        guard !windows.isEmpty else { throw UsageError.problem("Nothing metered on this plan") }
        return .ok(plan: (root["membershipType"] as? String)?.capitalized, windows: windows)
    }
}

// MARK: - Grok

/// The Grok CLI keeps its xAI session in ~/.grok/auth.json.
enum GrokUsage {
    static func fetch() async throws -> ProviderUsage {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
        guard let data = try? Data(contentsOf: url), let root = JSONValue.object(data) else { throw UsageError.notSetUp }
        // Only sessions issued by xAI's own sign-in; prefer one that hasn't expired.
        let entries = root.compactMap { key, value -> [String: Any]? in
            guard let entry = value as? [String: Any],
                  key.components(separatedBy: "::").first == "https://auth.x.ai"
                    || entry["oidc_issuer"] as? String == "https://auth.x.ai" else { return nil }
            return entry
        }
        let entry = entries.first { (JSONValue.date($0["expires_at"]) ?? .distantFuture) > Date() } ?? entries.first
        guard let token = entry?["key"] as? String, !token.isEmpty else { throw UsageError.notSetUp }

        let body = try await UsageHTTP.get(URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!,
                                           headers: ["Authorization": "Bearer \(token)",
                                                     "X-XAI-Token-Auth": "xai-grok-cli",
                                                     "Accept": "application/json"])
        guard let config = JSONValue.object(body)?["config"] as? [String: Any] else {
            throw UsageError.problem("Unexpected response")
        }
        let resetsAt = JSONValue.date((config["currentPeriod"] as? [String: Any])?["end"])
            ?? JSONValue.date(config["billingPeriodEnd"])
        var windows: [UsageWindow] = []
        if let percent = JSONValue.number(config["creditUsagePercent"]) {
            windows.append(UsageWindow(id: "credits", label: "Credits", used: percent / 100, resetsAt: resetsAt))
        } else {
            for product in config["productUsage"] as? [[String: Any]] ?? [] {
                guard let percent = JSONValue.number(product["usagePercent"]) else { continue }
                let name = product["product"] as? String ?? "Usage"
                windows.append(UsageWindow(id: name, label: name, used: percent / 100,
                                           resetsAt: resetsAt))
            }
        }
        guard !windows.isEmpty else { throw UsageError.problem("Nothing metered yet") }
        return .ok(plan: nil, windows: windows)
    }
}

// MARK: - Kimi Code

/// The Kimi Code CLI keeps its session in ~/.kimi-code/credentials/kimi-code.json.
enum KimiUsage {
    static func fetch() async throws -> ProviderUsage {
        let home = ProcessInfo.processInfo.environment["KIMI_CODE_HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi-code")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("credentials/kimi-code.json")),
              let root = JSONValue.object(data), let token = root["access_token"] as? String, !token.isEmpty
        else { throw UsageError.notSetUp }
        if let expires = JSONValue.number(root["expires_at"]), expires < Date().timeIntervalSince1970 {
            throw UsageError.problem("Open Kimi Code to refresh")
        }

        let body = try await UsageHTTP.get(URL(string: "https://api.kimi.com/coding/v1/usages")!,
                                           headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"])
        guard let response = JSONValue.object(body) else { throw UsageError.problem("Unexpected response") }
        var windows: [UsageWindow] = []
        for entry in response["limits"] as? [[String: Any]] ?? [] {
            guard let detail = entry["detail"] as? [String: Any], let window = row(detail, id: "rolling", label: "5h limit")
            else { continue }
            windows.append(window)
        }
        if let summary = response["usage"] as? [String: Any], let week = row(summary, id: "weekly", label: "Weekly limit") {
            windows.append(week)
        }
        guard !windows.isEmpty else { throw UsageError.problem("No usage limits on this account") }
        let plan = ((response["user"] as? [String: Any])?["membership"] as? [String: Any])?["level"] as? String
        return .ok(plan: plan?.replacingOccurrences(of: "LEVEL_", with: "").capitalized, windows: windows)
    }

    private static func row(_ detail: [String: Any], id: String, label: String) -> UsageWindow? {
        guard let limit = JSONValue.number(detail["limit"]), limit > 0 else { return nil }
        let used = JSONValue.number(detail["used"])
            ?? JSONValue.number(detail["remaining"]).map { limit - $0 }
        guard let used else { return nil }
        return UsageWindow(id: id, label: label, used: used / limit, resetsAt: JSONValue.date(detail["resetTime"]))
    }
}

// MARK: - OpenCode

/// OpenCode stores its Go plan key in ~/.local/share/opencode/auth.json.
enum OpenCodeUsage {
    static func fetch() async throws -> ProviderUsage {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode/auth.json")
        guard let data = try? Data(contentsOf: url), let entry = JSONValue.object(data)?["opencode-go"] else {
            throw UsageError.notSetUp
        }
        let token = (entry as? String)
            ?? ["key", "apiKey", "api_key", "token", "accessToken"]
                .lazy.compactMap { (entry as? [String: Any])?[$0] as? String }.first
        guard let token, !token.isEmpty else { throw UsageError.notSetUp }

        let body = try await UsageHTTP.get(URL(string: "https://opencode.ai/zen/go/v1/usage")!,
                                           headers: ["Authorization": "Bearer \(token)", "Accept": "application/json"])
        guard let usage = JSONValue.object(body)?["usage"] as? [String: Any] else {
            throw UsageError.problem("Unexpected response")
        }
        let windows = [("rolling", "5h limit"), ("weekly", "Weekly limit"), ("monthly", "Monthly limit")].compactMap { id, label -> UsageWindow? in
            guard let entry = usage[id] as? [String: Any], let percent = JSONValue.number(entry["percent"]) else { return nil }
            return UsageWindow(id: id, label: label, used: percent / 100, resetsAt: JSONValue.date(entry["resetsAt"]))
        }
        guard !windows.isEmpty else { throw UsageError.problem("Unexpected response") }
        return .ok(plan: "Go", windows: windows)
    }
}

// MARK: - Amp

/// The Amp CLI keeps its API key in ~/.local/share/amp/secrets.json; usage comes back as display text.
enum AmpUsage {
    static func fetch() async throws -> ProviderUsage {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/amp/secrets.json")
        guard let data = try? Data(contentsOf: url), let root = JSONValue.object(data),
              let token = ["apiKey@https://ampcode.com/", "apiKey@https://ampcode.com"]
                .lazy.compactMap({ root[$0] as? String }).first, !token.isEmpty
        else { throw UsageError.notSetUp }

        let body = try await UsageHTTP.get(
            URL(string: "https://ampcode.com/api/internal")!,
            headers: ["Authorization": "Bearer \(token)", "Content-Type": "application/json", "Accept": "application/json"],
            method: "POST",
            body: Data(#"{"jsonrpc":"2.0","method":"userDisplayBalanceInfo","params":{},"id":1}"#.utf8))
        guard let response = JSONValue.object(body),
              let text = ((response["result"] as? [String: Any]) ?? response)["displayText"] as? String
        else { throw UsageError.problem("Unexpected response") }
        let clean = text.replacingOccurrences(of: "**", with: "")

        // "Amp Pro Subscription: 72% agent usage and 90% orb usage remaining"
        if let fields = captures(#"Amp\s+(.+?)\s+(?:Subscription|Tier):.*?([0-9.]+)%.*?([0-9.]+)%"#, in: clean),
           let agent = Double(fields[1]), let orb = Double(fields[2]) {
            return .ok(plan: fields[0], windows: [
                UsageWindow(id: "agent", label: "Agent usage", used: (100 - agent) / 100, resetsAt: nil),
                UsageWindow(id: "orb", label: "Orb usage", used: (100 - orb) / 100, resetsAt: nil),
            ])
        }
        // "Amp Free: $4.20/$10 remaining (replenishes +$0.42/hour)"
        if let fields = captures(#"Amp Free:\s*\$([0-9.]+)/\$([0-9.]+)\s+remaining"#, in: clean),
           let remaining = Double(fields[0]), let total = Double(fields[1]), total > 0 {
            return .ok(plan: "Free", windows: [
                UsageWindow(id: "free", label: "Free allowance", used: 1 - remaining / total, resetsAt: nil),
            ])
        }
        throw UsageError.problem("Couldn't read Amp's balance")
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }
}

// MARK: - Custom

enum CustomUsage {
    static func fetch(_ provider: CustomAIProvider) async throws -> ProviderUsage {
        guard let url = URL(string: provider.url.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true
        else { throw UsageError.problem("Set a valid URL") }
        var headers = ["Accept": "application/json"]
        if let key = provider.apiKey, !provider.authHeader.isEmpty {
            headers[provider.authHeader] = provider.authPrefix + key
        }
        let data = try await UsageHTTP.get(url, headers: headers)
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw UsageError.problem("Not JSON") }

        func number(_ path: String) -> Double? { JSONValue.number(JSONValue.value(at: path, in: root)) }
        let used: Double?
        switch provider.mode {
        case .percent:
            used = number(provider.valuePath).map { $0 / 100 }
        case .usedAndLimit:
            used = number(provider.valuePath).flatMap { value in number(provider.limitPath).map { value / $0 } }
        case .remainingAndLimit:
            used = number(provider.valuePath).flatMap { value in number(provider.limitPath).map { 1 - value / $0 } }
        }
        guard let used, used.isFinite else { throw UsageError.problem("Value not found at that path") }
        let resetsAt = provider.resetPath.isEmpty ? nil : JSONValue.date(JSONValue.value(at: provider.resetPath, in: root))
        return .ok(plan: nil, windows: [UsageWindow(id: "custom", label: provider.label, used: used, resetsAt: resetsAt)])
    }
}

// MARK: - Small readers

enum JWT {
    static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        return Data(base64Encoded: payload).flatMap(JSONValue.object)
    }
}
